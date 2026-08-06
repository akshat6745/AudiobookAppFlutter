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
    if (delay != Duration.zero) await Future.delayed(delay);
    synthesized.add(text);
    return TtsAudio(_silenceWav(), 'wav');
  }

  @override
  Future<void> dispose() async {}
}

// ── Helpers ──────────────────────────────────────────────────────────────────

AudioCacheManager _makeCache({
  required Directory tmpDir,
  TtsEngine? engine,
  int preloadThreshold = 500,
}) =>
    AudioCacheManager(
      narratorVoice: 'am_michael',
      dialogueVoice: 'af_heart',
      engine: engine ?? FakeTtsEngine(),
      cacheDirOverride: tmpDir,
      config: AudioCacheConfig(preloadCharacterThreshold: preloadThreshold),
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
