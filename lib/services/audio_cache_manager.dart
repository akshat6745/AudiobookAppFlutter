import 'dart:async';
import 'dart:convert' show base64Encode;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/paragraph_audio.dart';
import 'offline_content_service.dart';
import 'saved_chapter_audio.dart';
import 'tts/remote_tts_engine.dart';
import 'tts/tts_engine.dart';

/// Cache key: (novel slug, chapter number, paragraph index). Using the full
/// triple — not just the paragraph index — is what makes chapter switches
/// safe: paragraph 10 of chapter 5 and paragraph 10 of chapter 6 are
/// structurally different keys and can never collide, no matter what order
/// their loads/preloads/evictions happen to finish in.
typedef _CacheKey = (String novel, int chapter, int index);

/// Thrown to reject an awaiter of an in-flight load when the playback
/// session changes (chapter switch, voice change, engine swap) before the
/// load finishes. Callers treat this the same as "no audio yet" — they
/// never see stale data.
class _StaleSessionException implements Exception {
  @override
  String toString() =>
      'AudioCacheManager: session changed before this request completed';
}

/// In-memory + on-disk cache for paragraph audio.
///
/// Port of the React Native `AudioCacheManager` with:
///   * Ultra-priority immediate-next preload
///   * Character threshold accumulator (independent of playback speed —
///     the player applies speed, not the cache)
///   * LRU-ish eviction (keep window around currentIndex)
///   * Offline-first lookup
///
/// ## Session safety
/// Every entry is keyed by `(novel, chapter, paragraphIndex)`, and every
/// context change ([setContext] with a new novel/chapter, [updateVoices],
/// [updateEngine]) bumps an internal generation counter. Any async load that
/// was in flight when the generation changed discards its result instead of
/// writing it into the cache — this is what prevents audio generated for a
/// previous chapter (or previous voice/engine) from ever being served under
/// a new one, even if that old request finishes late.
class AudioCacheManager {
  final Map<_CacheKey, ParagraphAudioData> _cache = {};
  final Map<_CacheKey, Completer<void>> _activeRequests = {};
  String _narratorVoice;
  String _dialogueVoice;
  final AudioCacheConfig _config;

  String? _currentNovelName;
  int? _currentChapterNumber;

  /// Bumped by [setContext] (chapter switch), [updateVoices], and
  /// [updateEngine] — the current playback session's identity. Async work
  /// captures this on entry and checks it again before mutating shared
  /// state; a mismatch means "this result belongs to a session that no
  /// longer exists" and is discarded.
  int _generation = 0;

  _OfflineBundle? _offlineCache;

  TtsEngine _engine;
  bool _useSavedAudio = false;
  final SavedChapterAudio _savedAudio;

  // Preload pump: keep _config.preloadCharacterThreshold characters of upcoming
  // audio (paragraphs after _preloadAnchor, not counting it) ready or generating.
  int _preloadAnchor = -1;
  List<String> _preloadParagraphs = const [];
  Timer? _preloadTimer;

  /// Optional override for the audio cache directory. When provided the
  /// manager writes WAV/MP3 files here instead of the platform temp dir.
  /// Used by unit tests to avoid platform-channel calls.
  final Directory? _cacheDirOverride;

  AudioCacheManager({
    required String narratorVoice,
    required String dialogueVoice,
    AudioCacheConfig config = const AudioCacheConfig(),
    TtsEngine? engine,
    Directory? cacheDirOverride,
    SavedChapterAudio? savedAudio,
  })  : _narratorVoice = narratorVoice,
        _dialogueVoice = dialogueVoice,
        _engine = engine ?? RemoteTtsEngine(),
        _savedAudio = savedAudio ?? SavedChapterAudio(),
        _config = config,
        _cacheDirOverride = cacheDirOverride;

  // ---- Public API ----

  /// Switch the active novel/chapter. When it actually changes, this starts
  /// a new playback session: the generation counter is bumped, the preload
  /// timer and buffer are reset, and any request still in flight for the
  /// old chapter is failed so its awaiter bails out immediately instead of
  /// resolving into (or blocking on) stale state. This happens synchronously
  /// — the reset is atomic with respect to any caller of [getAudio].
  void setContext(String novelName, int chapterNumber) {
    final isNew = novelName != _currentNovelName ||
        chapterNumber != _currentChapterNumber;
    _currentNovelName = novelName;
    _currentChapterNumber = chapterNumber;
    if (isNew) {
      _offlineCache = null;
      _startNewSession();
    }
  }

  /// Update voices. Clears the cache when voices actually change.
  Future<void> updateVoices(String narrator, String dialogue) async {
    if (_narratorVoice == narrator && _dialogueVoice == dialogue) return;
    _narratorVoice = narrator;
    _dialogueVoice = dialogue;
    await clearCache();
  }

  /// Play stored R2 Opus for this chapter instead of synthesizing.
  /// Clears cached clips when the source changes so a paragraph is not
  /// replayed from the other engine.
  Future<void> setUseSavedAudio(bool enabled) async {
    if (_useSavedAudio == enabled) return;
    _useSavedAudio = enabled;
    await clearCache();
  }

  /// Swap the TTS engine (remote ↔ on-device Kokoro). Releases the previous
  /// engine's resources (e.g. the sherpa worker isolate + loaded model) and
  /// clears cached audio when the engine kind changes, because the cached
  /// format differs (mp3 for remote, wav for on-device).
  Future<void> updateEngine(TtsEngine engine) async {
    final old = _engine;
    if (identical(old, engine)) return;
    final sameKind = old.runtimeType == engine.runtimeType;
    _engine = engine;
    await old.dispose();
    if (!sameKind) {
      await clearCache();
    }
  }

  bool isAudioReady(int index) {
    final cached = _cache[_keyFor(index)];
    return cached != null && cached.isValid;
  }

  /// Get audio for a paragraph, awaiting its availability.
  /// Triggers preload as a side effect.
  Future<ParagraphAudioData?> getAudio({
    required int paragraphIndex,
    required String paragraphText,
    required List<String> allParagraphs,
  }) async {
    final key = _keyFor(paragraphIndex);

    final cached = _cache[key];
    if (cached != null && cached.isValid && cached.paragraphText == paragraphText) {
      _triggerPreload(paragraphIndex, allParagraphs);
      return cached;
    }

    final inFlight = _activeRequests[key];
    if (inFlight != null) {
      try {
        await inFlight.future;
        final loaded = _cache[key];
        if (loaded != null &&
            loaded.isValid &&
            loaded.paragraphText == paragraphText) {
          _triggerPreload(paragraphIndex, allParagraphs);
          return loaded;
        }
      } catch (_) {
        // Stale session or load failure — fall through to a fresh load.
      }
    }

    final data = await _loadAudioForParagraph(paragraphIndex, paragraphText);
    if (data != null && data.isValid) {
      _triggerPreload(paragraphIndex, allParagraphs);
    }
    return data;
  }

  /// Top up the preload buffer (e.g. on app pause). [count] is retained for
  /// API compatibility; buffer depth is character-driven now.
  void preloadAhead(int currentIndex, List<String> allParagraphs,
      {int count = 15}) {
    _preloadAnchor = currentIndex;
    _preloadParagraphs = allParagraphs;
    _pumpPreload();
  }

  /// Clear all cached audio and start a new session. Used on voice/engine
  /// change (where every cached byte is now wrong) and available for
  /// explicit full resets.
  Future<void> clearCache() async {
    _startNewSession();
    final uris = _cache.values
        .where((v) => v.audioUri != null)
        .map((v) => v.audioUri!)
        .toList();
    _cache.clear();
    _offlineCache = null;
    if (!kIsWeb) {
      for (final path in uris) {
        try {
          final f = File(path);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
    }
  }

  // ---- Internals ----

  _CacheKey _keyFor(int index) =>
      (_currentNovelName ?? '', _currentChapterNumber ?? -1, index);

  /// Bumps the generation, cancels the preload timer/buffer, and fails any
  /// in-flight completers so their awaiters unblock immediately instead of
  /// resolving into a session that no longer exists. This is the "atomic
  /// queue reset" — every field it touches is mutated synchronously, before
  /// any await, so there is no window where old and new session state can
  /// interleave.
  void _startNewSession() {
    _generation++;
    _preloadTimer?.cancel();
    _preloadTimer = null;
    _preloadAnchor = -1;
    _preloadParagraphs = const [];
    if (_activeRequests.isNotEmpty) {
      final stale = _activeRequests.values.toList();
      _activeRequests.clear();
      for (final c in stale) {
        if (!c.isCompleted) c.completeError(_StaleSessionException());
      }
    }
  }

  Future<ParagraphAudioData?> _loadAudioForParagraph(
    int index,
    String text,
  ) async {
    final key = _keyFor(index);
    final gen = _generation;

    final existing = _cache[key];
    if (existing != null && existing.isValid && existing.paragraphText == text) {
      return existing;
    }

    if (_activeRequests.containsKey(key)) {
      return null;
    }

    final completer = Completer<void>();
    _activeRequests[key] = completer;
    // A session teardown ([_startNewSession]) can fail this completer before
    // any concurrent `getAudio` call has started listening to it. Attach a
    // swallow-error listener up front so that case never surfaces as an
    // unhandled zone exception — real listeners (the "in flight" branch of
    // [getAudio]) still get the error via their own `await`.
    unawaited(completer.future.catchError((_) {}));

    final entry = ParagraphAudioData(
      paragraphIndex: index,
      paragraphText: text,
      isLoading: true,
    );
    _cache[key] = entry;

    try {
      await _loadInternal(key, gen, index, text, entry);

      if (gen != _generation) {
        // The session moved on while this was in flight — discard rather
        // than surface (possibly stale-context) audio as valid.
        _cache.remove(key);
        if (!completer.isCompleted) completer.complete();
        return null;
      }

      if (entry.isValid) {
        if (!completer.isCompleted) completer.complete();
        return entry;
      } else {
        if (!completer.isCompleted) completer.complete();
        _cache.remove(key);
        return null;
      }
    } catch (e) {
      entry.isLoading = false;
      entry.audioReceived = false;
      if (!completer.isCompleted) completer.completeError(e);
      return null;
    } finally {
      _activeRequests.remove(key);
      // A load finished — advance the preload buffer, but only for the
      // session it actually belongs to.
      if (gen == _generation) {
        _pumpPreload();
      }
    }
  }

  Future<void> _loadInternal(
    _CacheKey key,
    int gen,
    int index,
    String text,
    ParagraphAudioData entry,
  ) async {
    final novel = key.$1;
    final chapter = key.$2;

    if (_useSavedAudio) {
      final bytes = await _savedAudio.downloadParagraph(
        novel: novel,
        chapter: chapter,
        playbackIndex: index,
      );
      if (gen != _generation) return;
      if (bytes == null) {
        throw StateError(
          'AudioCacheManager: recorded audio missing for paragraph $index',
        );
      }
      if (kIsWeb) {
        entry.audioUri = 'data:audio/ogg;base64,${base64Encode(bytes)}';
      } else {
        final cachePath = await _ttsCachePath(index, 'ogg');
        await File(cachePath).writeAsBytes(bytes);
        if (gen != _generation) {
          try {
            await File(cachePath).delete();
          } catch (_) {}
          return;
        }
        entry.audioUri = cachePath;
      }
      entry.audioReceived = true;
      entry.isLoading = false;
      _cache[key] = entry;
      return;
    }

    // 1. Offline-first lookup (file system only available on mobile/desktop).
    if (!kIsWeb) {
      try {
        var offline = _offlineCache;
        if (offline == null || offline.novel != novel || offline.chapter != chapter) {
          final loaded = await _loadOfflineBundle(novel, chapter);
          if (gen != _generation) return; // session moved on mid-lookup
          offline = loaded;
          // Only promote to the shared cache slot if it still matches the
          // *current* context — an old lookup resolving late must never
          // clobber a newer bundle that's already loaded.
          if (novel == _currentNovelName && chapter == _currentChapterNumber) {
            _offlineCache = offline;
          }
        }

        if (offline != null && offline.paragraphCount > 0) {
          String? uri;
          if (index == 0) {
            uri = offline.titleAudio;
          } else if (index > 0 && index <= offline.paragraphCount) {
            uri = offline.paragraphAudios[index - 1];
          }
          if (uri != null) {
            final f = File(uri);
            if (f.existsSync() && (await f.length()) > 1024) {
              if (gen != _generation) return;
              entry.audioReceived = true;
              entry.audioUri = uri;
              entry.isLoading = false;
              _cache[key] = entry;
              return;
            }
          }
        }
      } catch (_) {
        // Fall through to TTS
      }
    }

    if (gen != _generation) return;

    // 2. On-device (Kokoro) or remote TTS via the active engine.
    final audio = await _engine.synthParagraph(
      text: text,
      paragraphVoice: _narratorVoice,
      dialogueVoice: _dialogueVoice,
    );

    if (gen != _generation) return; // discard — session moved on mid-synthesis

    // Mirror the >1024-byte sanity check used for offline-downloaded files
    // (see offline_content_service.dart) so a truncated/corrupt synthesis
    // result — e.g. the backend returning an empty/error body with a 200 —
    // fails loudly instead of being cached and played as silence/noise.
    if (audio.bytes.length <= 1024) {
      throw StateError(
        'AudioCacheManager: synthesized audio too small '
        '(${audio.bytes.length} bytes) to be valid',
      );
    }

    if (kIsWeb) {
      // Web has no writable file system — store audio as an in-memory data URI
      // so just_audio can load it via a standard <audio src="data:..."> element.
      final mime = audio.format == 'wav' ? 'audio/wav' : 'audio/mpeg';
      entry.audioUri = 'data:$mime;base64,${base64Encode(audio.bytes)}';
    } else {
      final cachePath = await _ttsCachePath(index, audio.format);
      await File(cachePath).writeAsBytes(audio.bytes);
      if (gen != _generation) {
        // Session moved on while writing — clean up the orphaned file
        // instead of leaving it referenced by a discarded entry.
        try {
          await File(cachePath).delete();
        } catch (_) {}
        return;
      }
      entry.audioUri = cachePath;
    }

    entry.audioReceived = true;
    entry.isLoading = false;
    _cache[key] = entry;
  }

  Future<_OfflineBundle?> _loadOfflineBundle(String novel, int chapter) async {
    final result = await offlineContentService.getOfflineChapterAudio(
      novel,
      chapter,
    );
    if (result == null) return null;
    return _OfflineBundle(
      novel: novel,
      chapter: chapter,
      titleAudio: result.titleAudio,
      paragraphAudios: result.paragraphAudios,
      paragraphCount: result.paragraphAudios.length,
    );
  }

  Future<String> _ttsCachePath(int index, String ext) async {
    final base = _cacheDirOverride ?? await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'audio_cache'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return p.join(
      dir.path,
      'audio_${index}_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
  }

  // ---- Preload engine ----

  void _triggerPreload(int currentIndex, List<String> allParagraphs) {
    _preloadAnchor = currentIndex;
    _preloadParagraphs = allParagraphs;
    final gen = _generation;
    _preloadTimer?.cancel();
    _preloadTimer = Timer(const Duration(milliseconds: 1), () {
      if (gen != _generation) return; // session changed before this fired
      _pumpPreload();
      _cleanupCache(currentIndex);
    });
  }

  /// Keep [AudioCacheConfig.preloadCharacterThreshold] characters of *upcoming*
  /// audio (paragraphs after [_preloadAnchor], not counting it) ready or being
  /// generated, generating up to [AudioCacheConfig.maxConcurrentPreloads]
  /// paragraphs at once (see that field's doc for why this is safe for both
  /// engines). Each completed load re-invokes this, advancing the buffer and
  /// topping up the concurrency window until the target is met (or the
  /// chapter ends).
  void _pumpPreload() {
    final anchor = _preloadAnchor;
    final paras = _preloadParagraphs;
    if (anchor < 0 || paras.isEmpty) return;

    var bufferedChars = 0;
    var inFlightCount = 0;
    final toStart = <int>[];

    for (var i = anchor + 1; i < paras.length; i++) {
      if (bufferedChars >= _config.preloadCharacterThreshold) break;

      final key = _keyFor(i);
      final cached = _cache[key];
      final ready = cached != null && cached.isValid;
      final loading =
          _activeRequests.containsKey(key) || (cached != null && cached.isLoading);
      if (ready || loading) {
        bufferedChars += paras[i].length;
        if (loading) inFlightCount++;
      } else if (inFlightCount + toStart.length < _config.maxConcurrentPreloads) {
        // Tentatively commit to starting this one now, counting its chars
        // toward the target immediately — otherwise a full concurrency
        // window of "about to start" paragraphs wouldn't stop the scan from
        // also queuing paragraphs well past the character threshold.
        toStart.add(i);
        bufferedChars += paras[i].length;
      } else {
        // No free concurrency slot left — stop; the next completed load
        // re-invokes this and picks up scanning from here.
        break;
      }
    }

    for (final i in toStart) {
      _loadAudioForParagraph(i, paras[i]);
    }
  }

  /// Index one past the last paragraph within the upcoming character window —
  /// the furthest paragraph to keep buffered ahead of [currentIndex].
  int _preloadHorizon(int currentIndex) {
    final paras = _preloadParagraphs;
    if (paras.isEmpty) return currentIndex + _config.maxPreloadDistance;
    var chars = 0;
    var i = currentIndex + 1;
    while (i < paras.length && chars < _config.preloadCharacterThreshold) {
      chars += paras[i].length;
      i++;
    }
    return i;
  }

  void _cleanupCache(int currentIndex) {
    if (_cache.length <= _config.maxCacheSize) return;

    const keepBefore = 3;
    final keepStart = max(0, currentIndex - keepBefore);
    final keepEnd = _preloadHorizon(currentIndex);
    final novel = _currentNovelName;
    final chapter = _currentChapterNumber;

    final toDelete = <_CacheKey>[];
    final filesToDelete = <String>[];

    _cache.forEach((key, data) {
      // Entries from a chapter other than the current one are always
      // evictable — they can only be here because a stale load slipped
      // through before its session was fully torn down.
      final sameContext = key.$1 == novel && key.$2 == chapter;
      final index = key.$3;
      if (!sameContext || index < keepStart || index > keepEnd) {
        toDelete.add(key);
        if (data.audioUri != null) filesToDelete.add(data.audioUri!);
      }
    });

    for (final key in toDelete) {
      _cache.remove(key);
    }

    if (!kIsWeb) {
      for (final path in filesToDelete) {
        () async {
          try {
            final f = File(path);
            if (f.existsSync()) await f.delete();
          } catch (_) {}
        }();
      }
    }
  }
}

class _OfflineBundle {
  final String novel;
  final int chapter;
  final String? titleAudio;
  final List<String?> paragraphAudios;
  final int paragraphCount;
  _OfflineBundle({
    required this.novel,
    required this.chapter,
    required this.titleAudio,
    required this.paragraphAudios,
    required this.paragraphCount,
  });
}
