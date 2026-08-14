import 'dart:io';
import 'dart:typed_data';

import 'package:audiobook_app/models/paragraph_audio.dart';
import 'package:audiobook_app/services/audio_cache_manager.dart';
import 'package:audiobook_app/services/tts/tts_engine.dart';
import 'package:audiobook_app/services/tts/wav_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Fake engine ──────────────────────────────────────────────────────────────

class FakeTtsEngine extends TtsEngine {
  final List<String> synthesized = [];
  Duration delay;

  /// Tracks overlap between concurrent [synthParagraph] calls, so tests can
  /// assert the preload pump actually dispatches several at once instead of
  /// waiting for each to finish before starting the next.
  int _active = 0;
  int peakConcurrent = 0;

  FakeTtsEngine({this.delay = Duration.zero});

  /// Minimal valid WAV (44 header + 2400 samples × 2 bytes = 4844 bytes total).
  /// 2400 samples at 24 kHz = 100 ms of silence — valid for just_audio.
  static Uint8List _silenceWav() =>
      encodeWavPcm16(Float32List(2400), 24000);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<TtsAudio> synthParagraph({
    required String text,
    required String paragraphVoice,
    required String dialogueVoice,
  }) async {
    _active++;
    if (_active > peakConcurrent) peakConcurrent = _active;
    try {
      if (delay != Duration.zero) await Future.delayed(delay);
      synthesized.add(text);
      return TtsAudio(_silenceWav(), 'wav');
    } finally {
      _active--;
    }
  }

  @override
  Future<void> dispose() async {}
}

// ── Helpers ──────────────────────────────────────────────────────────────────

AudioCacheManager _makeCache({
  required Directory tmpDir,
  TtsEngine? engine,
  int preloadThreshold = 500,
  int maxConcurrentPreloads = 3,
}) =>
    AudioCacheManager(
      narratorVoice: 'am_michael',
      dialogueVoice: 'af_heart',
      engine: engine ?? FakeTtsEngine(),
      cacheDirOverride: tmpDir,
      config: AudioCacheConfig(
        preloadCharacterThreshold: preloadThreshold,
        maxConcurrentPreloads: maxConcurrentPreloads,
      ),
    );

/// Returns paragraphs whose total character count exceeds [totalChars].
List<String> _paragraphs({int count = 10, int charsEach = 100}) =>
    List.generate(count, (i) => 'P$i: ${'x' * (charsEach - 4)}');

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('audio_cache_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('getAudio — basic synthesis', () {
    test('returns valid audio data for a paragraph', () async {
      final engine = FakeTtsEngine();
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);
      cache.setContext('novel-slug', 1);

      final paras = _paragraphs();
      final result = await cache.getAudio(
        paragraphIndex: 0,
        paragraphText: paras[0],
        allParagraphs: paras,
      );

      expect(result, isNotNull);
      expect(result!.isValid, isTrue);
      expect(result.audioUri, isNotNull);
      expect(engine.synthesized, contains(paras[0]));
    });

    test('caches result — second call does not re-synthesise', () async {
      final engine = FakeTtsEngine();
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs();

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);
      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);

      expect(engine.synthesized.length, 1,
          reason: 'engine should be called only once per paragraph');
    });

    test('audio file written to disk and is non-empty', () async {
      final engine = FakeTtsEngine();
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs();

      final result = await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);

      expect(result, isNotNull);
      final file = File(result!.audioUri!);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(44),
          reason: 'WAV file should be larger than its header');
    });

    test('audio file starts with RIFF header', () async {
      final engine = FakeTtsEngine();
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs();

      final result = await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);

      final bytes = File(result!.audioUri!).readAsBytesSync();
      // 'RIFF' magic at offset 0
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    });
  });

  group('preload pump — character threshold', () {
    test('pump starts generating the next paragraph after getAudio', () async {
      final engine = FakeTtsEngine();
      // threshold = 200 chars; each paragraph = 100 chars → need 2 paragraphs ahead
      final cache =
          _makeCache(tmpDir: tmpDir, engine: engine, preloadThreshold: 200);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs(count: 6, charsEach: 100);

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);

      // Give the pump a moment to fire (Timer 1ms + async synthesis)
      await Future.delayed(const Duration(milliseconds: 100));

      expect(engine.synthesized.length, greaterThanOrEqualTo(2),
          reason: 'pump should have started at least paragraph 1 ahead');
    });

    test('pump does not exceed the character threshold', () async {
      final engine = FakeTtsEngine();
      // Threshold = 150 chars, each paragraph = 100 chars → max 1 ahead
      final cache =
          _makeCache(tmpDir: tmpDir, engine: engine, preloadThreshold: 150);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs(count: 10, charsEach: 100);

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);

      await Future.delayed(const Duration(milliseconds: 150));

      // Only index 0 was explicitly requested; pump adds at most 1 (≤150 chars)
      // The total should be 0 + 1 preloaded = 2 max
      expect(engine.synthesized.length, lessThanOrEqualTo(3),
          reason: 'pump should not over-generate beyond threshold');
    });

    test('pump stops at end of chapter', () async {
      final engine = FakeTtsEngine();
      // Threshold large enough to want the whole chapter
      final cache =
          _makeCache(tmpDir: tmpDir, engine: engine, preloadThreshold: 5000);
      cache.setContext('novel-slug', 1);
      // Only 3 short paragraphs
      final paras = _paragraphs(count: 3, charsEach: 50);

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);

      await Future.delayed(const Duration(milliseconds: 300));

      // Should never synthesize more paragraphs than exist
      expect(engine.synthesized.length, lessThanOrEqualTo(paras.length));
    });

    test('preloadAhead seeds the pump with the correct anchor', () async {
      final engine = FakeTtsEngine();
      final cache =
          _makeCache(tmpDir: tmpDir, engine: engine, preloadThreshold: 200);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs(count: 8, charsEach: 80);

      // Simulate user pausing at paragraph 3 — preloadAhead from there
      cache.preloadAhead(3, paras);
      await Future.delayed(const Duration(milliseconds: 200));

      // Engine should have been called for paragraphs after index 3
      expect(engine.synthesized.any((t) => paras.indexOf(t) > 3), isTrue);
    });
  });

  group('preload pump — concurrency', () {
    test('dispatches multiple preloads concurrently, not one at a time',
        () async {
      final engine = FakeTtsEngine(delay: const Duration(milliseconds: 50));
      // Threshold wide enough to want several paragraphs ahead.
      final cache = _makeCache(
          tmpDir: tmpDir, engine: engine, preloadThreshold: 1000);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs(count: 8, charsEach: 100);

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);

      // Give the pump time to fire and the fake engine's delayed calls to
      // overlap, but not enough for them to finish serially (3 × 50ms).
      await Future.delayed(const Duration(milliseconds: 120));

      expect(engine.peakConcurrent, greaterThan(1),
          reason: 'preload should overlap requests instead of awaiting '
              'each one before starting the next');
    });

    test('never exceeds maxConcurrentPreloads in-flight requests', () async {
      final engine = FakeTtsEngine(delay: const Duration(milliseconds: 30));
      final cache = _makeCache(
        tmpDir: tmpDir,
        engine: engine,
        preloadThreshold: 5000,
        maxConcurrentPreloads: 2,
      );
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs(count: 10, charsEach: 100);

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);
      await Future.delayed(const Duration(milliseconds: 400));

      expect(engine.peakConcurrent, lessThanOrEqualTo(2),
          reason: 'the concurrency cap must never be exceeded, regardless '
              'of how large the character-threshold buffer is');
    });
  });

  group('voice change', () {
    test('updateVoices clears the cache', () async {
      final engine = FakeTtsEngine();
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs();

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);
      expect(cache.isAudioReady(0), isTrue);

      await cache.updateVoices('af_sky', 'am_adam');
      expect(cache.isAudioReady(0), isFalse,
          reason: 'cache should be cleared after voice change');
    });

    test('updateVoices with same values keeps the cache', () async {
      final engine = FakeTtsEngine();
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs();

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);
      expect(cache.isAudioReady(0), isTrue);

      // Same voices — should be a no-op
      await cache.updateVoices('am_michael', 'af_heart');
      expect(cache.isAudioReady(0), isTrue,
          reason: 'cache should survive identical voice update');
    });
  });

  group('engine swap', () {
    test('updateEngine disposes the old engine', () async {
      bool disposed = false;

      final oldEngine = FakeTtsEngine();
      final disposableFake = _DisposableEngine(onDispose: () => disposed = true);

      final cache = _makeCache(tmpDir: tmpDir, engine: disposableFake);
      cache.setContext('novel-slug', 1);

      await cache.updateEngine(oldEngine);
      expect(disposed, isTrue);
    });

    test('updateEngine with same instance is a no-op', () async {
      final engine = FakeTtsEngine();
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs();

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);
      expect(cache.isAudioReady(0), isTrue);

      await cache.updateEngine(engine); // same instance
      expect(cache.isAudioReady(0), isTrue,
          reason: 'no-op update should not clear cache');
    });
  });

  group('chapter switch — session safety (regression for the audio-leak bug)',
      () {
    test(
        'audio generated for a previous chapter never leaks into the new '
        'chapter at the same paragraph index', () async {
      final engine = FakeTtsEngine(delay: const Duration(milliseconds: 50));
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);

      cache.setContext('novel-slug', 5);
      final ch5Paras = _paragraphs(count: 5, charsEach: 100);
      // Kick off a slow load for chapter 5, paragraph 2 — don't await it.
      final ch5Future = cache.getAudio(
        paragraphIndex: 2,
        paragraphText: ch5Paras[2],
        allParagraphs: ch5Paras,
      );

      // Switch chapters before the chapter-5 load finishes.
      cache.setContext('novel-slug', 6);
      final ch6Paras = _paragraphs(count: 5, charsEach: 100);

      // Request the same index (2) under chapter 6 — must synthesize fresh
      // chapter-6 audio, never chapter 5's late-resolving result.
      final ch6Result = await cache.getAudio(
        paragraphIndex: 2,
        paragraphText: ch6Paras[2],
        allParagraphs: ch6Paras,
      );

      expect(ch6Result, isNotNull);
      expect(ch6Result!.paragraphText, ch6Paras[2]);

      // The chapter-5 request must resolve (not hang) even though its
      // session was torn down mid-flight — it should discard, not error out
      // the caller.
      final ch5Result = await ch5Future;
      expect(ch5Result, isNull,
          reason: 'a request from a torn-down session resolves to null, '
              'never to (possibly mismatched) audio');

      // Re-querying chapter 6 index 2 must still be chapter 6's audio.
      final again = await cache.getAudio(
        paragraphIndex: 2,
        paragraphText: ch6Paras[2],
        allParagraphs: ch6Paras,
      );
      expect(again!.paragraphText, ch6Paras[2]);
    });

    test(
        "a preload started for the previous chapter never populates the "
        "new chapter's cache at the same index", () async {
      final engine = FakeTtsEngine();
      final cache =
          _makeCache(tmpDir: tmpDir, engine: engine, preloadThreshold: 5000);
      cache.setContext('novel-slug', 1);
      final ch1Paras = _paragraphs(count: 10, charsEach: 100);

      await cache.getAudio(
          paragraphIndex: 0,
          paragraphText: ch1Paras[0],
          allParagraphs: ch1Paras);
      // A preload for chapter-1 paragraph 1 may now be in flight.

      // Switch chapters immediately, before that preload settles.
      cache.setContext('novel-slug', 2);
      final ch2Paras = _paragraphs(count: 10, charsEach: 100);

      // Let any in-flight chapter-1 work settle.
      await Future.delayed(const Duration(milliseconds: 50));

      // Chapter 2's index 1 must not appear "ready" just because a stale
      // chapter-1 preload wrote to it.
      expect(cache.isAudioReady(1), isFalse,
          reason: 'index 1 must require a fresh synthesis under the new '
              'chapter, not inherit chapter 1\'s cached audio');

      final result = await cache.getAudio(
          paragraphIndex: 1,
          paragraphText: ch2Paras[1],
          allParagraphs: ch2Paras);
      expect(result!.paragraphText, ch2Paras[1]);
    });

    test(
        'a cache hit with mismatched paragraph text triggers a fresh '
        'synthesis instead of returning stale content', () async {
      final engine = FakeTtsEngine();
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);
      cache.setContext('novel-slug', 1);
      final paras = _paragraphs();

      await cache.getAudio(
          paragraphIndex: 0, paragraphText: paras[0], allParagraphs: paras);
      expect(engine.synthesized, [paras[0]]);

      // Same index, different text (e.g. the chapter content changed) — must
      // not silently return the old audio.
      const newText = 'completely different paragraph text';
      final result = await cache.getAudio(
          paragraphIndex: 0, paragraphText: newText, allParagraphs: paras);

      expect(result!.paragraphText, newText);
      expect(engine.synthesized, contains(newText));
    });

    test(
        'switching chapters fails in-flight requests so their awaiters '
        'resolve instead of hanging', () async {
      final engine = FakeTtsEngine(delay: const Duration(milliseconds: 200));
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);
      cache.setContext('novel-slug', 1);
      final ch1Paras = _paragraphs();

      final pending = cache.getAudio(
          paragraphIndex: 0,
          paragraphText: ch1Paras[0],
          allParagraphs: ch1Paras);

      // Switch before the slow synth resolves.
      await Future.delayed(const Duration(milliseconds: 10));
      cache.setContext('novel-slug', 2);

      // The original request must resolve (not hang forever) even though
      // its session was torn down mid-flight.
      final result = await pending.timeout(const Duration(seconds: 2));
      expect(result, isNull);
    });

    test(
        'the same paragraph index in two different chapters caches '
        'independently and never collides', () async {
      final engine = FakeTtsEngine();
      final cache = _makeCache(tmpDir: tmpDir, engine: engine);

      cache.setContext('novel-slug', 1);
      final ch1Paras = _paragraphs(count: 3, charsEach: 60);
      await cache.getAudio(
          paragraphIndex: 0,
          paragraphText: ch1Paras[0],
          allParagraphs: ch1Paras);

      cache.setContext('novel-slug', 2);
      // isAudioReady is scoped to the *current* context (chapter 2), so the
      // chapter-1 entry at the same index must not be visible here.
      expect(cache.isAudioReady(0), isFalse);

      final ch2Paras = _paragraphs(count: 3, charsEach: 60);
      final result = await cache.getAudio(
          paragraphIndex: 0,
          paragraphText: ch2Paras[0],
          allParagraphs: ch2Paras);
      expect(result!.paragraphText, ch2Paras[0]);

      // Switching back to chapter 1 must still see its own (still-valid)
      // cached entry rather than chapter 2's.
      cache.setContext('novel-slug', 1);
      expect(cache.isAudioReady(0), isTrue);
    });
  });
}

class _DisposableEngine extends TtsEngine {
  final void Function() onDispose;
  _DisposableEngine({required this.onDispose});

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<TtsAudio> synthParagraph({
    required String text,
    required String paragraphVoice,
    required String dialogueVoice,
  }) async =>
      TtsAudio(FakeTtsEngine._silenceWav(), 'wav');

  @override
  Future<void> dispose() async => onDispose();
}
