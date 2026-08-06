import 'dart:async';
import 'dart:convert' show base64Encode;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/paragraph_audio.dart';
import 'offline_content_service.dart';
import 'tts/remote_tts_engine.dart';
import 'tts/tts_engine.dart';

/// In-memory + on-disk cache for paragraph audio.
///
/// Port of the React Native `AudioCacheManager` with:
///   * Ultra-priority immediate-next preload
///   * Character threshold accumulator
///   * Speed-adaptive distance
///   * LRU-ish eviction (keep window around currentIndex)
///   * Offline-first lookup
class AudioCacheManager {
  final Map<int, ParagraphAudioData> _cache = {};
  final Map<int, Completer<void>> _activeRequests = {};
  String _narratorVoice;
  String _dialogueVoice;
  final AudioCacheConfig _config;

  String? _currentNovelName;
  int? _currentChapterNumber;

  _OfflineBundle? _offlineCache;

  TtsEngine _engine;

  // Preload pump: keep _config.preloadCharacterThreshold characters of upcoming
  // audio (paragraphs after _preloadAnchor, not counting it) ready or generating.
  int _preloadAnchor = -1;
  List<String> _preloadParagraphs = const [];

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
  })  : _narratorVoice = narratorVoice,
        _dialogueVoice = dialogueVoice,
        _engine = engine ?? RemoteTtsEngine(),
        _config = config,
        _cacheDirOverride = cacheDirOverride;

  // ---- Public API ----

  void setContext(String novelName, int chapterNumber) {
    final isNew = novelName != _currentNovelName ||
        chapterNumber != _currentChapterNumber;
    if (isNew) {
      _offlineCache = null;
    }
    _currentNovelName = novelName;
    _currentChapterNumber = chapterNumber;
  }

  void setCurrentlyPlaying(int? index) {
    // Used as a hint; currently no-op after removing unused field.
  }

  void setPlaybackSpeed(double speed) {
    // No-op: the preload buffer is character-based, independent of speed.
    // Playback speed is applied by the audio player, not here.
  }

  /// Update voices. Clears the cache when voices actually change.
  Future<void> updateVoices(String narrator, String dialogue) async {
    if (_narratorVoice == narrator && _dialogueVoice == dialogue) return;
    _narratorVoice = narrator;
    _dialogueVoice = dialogue;
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
    final cached = _cache[index];
    return cached != null && cached.isValid;
  }

  /// Get audio for a paragraph, awaiting its availability.
  /// Triggers preload as a side effect.
  Future<ParagraphAudioData?> getAudio({
    required int paragraphIndex,
    required String paragraphText,
    required List<String> allParagraphs,
  }) async {
    final cached = _cache[paragraphIndex];
    if (cached != null && cached.isValid) {
      _triggerPreload(paragraphIndex, allParagraphs);
      return cached;
    }

    if (_activeRequests.containsKey(paragraphIndex)) {
      try {
        await _activeRequests[paragraphIndex]!.future;
        final loaded = _cache[paragraphIndex];
        if (loaded != null && loaded.isValid) {
          _triggerPreload(paragraphIndex, allParagraphs);
          return loaded;
        }
      } catch (_) {}
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

  Future<void> clearCache() async {
    final uris = _cache.values
        .where((v) => v.audioUri != null)
        .map((v) => v.audioUri!)
        .toList();
    _cache.clear();
    _activeRequests.clear();
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

  Future<ParagraphAudioData?> _loadAudioForParagraph(
    int index,
    String text,
  ) async {
    final existing = _cache[index];
    if (existing != null && existing.isValid) return existing;

    if (_activeRequests.containsKey(index)) {
      return null;
    }

    final completer = Completer<void>();
    _activeRequests[index] = completer;

    final entry = ParagraphAudioData(
      paragraphIndex: index,
      paragraphText: text,
      isLoading: true,
    );
    _cache[index] = entry;

    try {
      await _loadInternal(index, text, entry);
      if (entry.isValid) {
        completer.complete();
        return entry;
      } else {
        completer.complete();
        _cache.remove(index);
        return null;
      }
    } catch (e) {
      entry.isLoading = false;
      entry.audioReceived = false;
      completer.completeError(e);
      return null;
    } finally {
      _activeRequests.remove(index);
      // A load finished — advance the preload buffer to the next paragraph.
      _pumpPreload();
    }
  }

  Future<void> _loadInternal(
    int index,
    String text,
    ParagraphAudioData entry,
  ) async {
    // 1. Offline-first lookup (file system only available on mobile/desktop)
    if (!kIsWeb && _currentNovelName != null && _currentChapterNumber != null) {
      try {
        _offlineCache ??= await _loadOfflineBundle(
          _currentNovelName!,
          _currentChapterNumber!,
        );

        final offline = _offlineCache;
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
              entry.audioReceived = true;
              entry.audioUri = uri;
              entry.isLoading = false;
              _cache[index] = entry;
              return;
            }
          }
        }
      } catch (_) {
        // Fall through to TTS
      }
    }

    // 2. On-device (Kokoro) or remote TTS via the active engine.
    final audio = await _engine.synthParagraph(
      text: text,
      paragraphVoice: _narratorVoice,
      dialogueVoice: _dialogueVoice,
    );

    if (kIsWeb) {
      // Web has no writable file system — store audio as an in-memory data URI
      // so just_audio can load it via a standard <audio src="data:..."> element.
      final mime = audio.format == 'wav' ? 'audio/wav' : 'audio/mpeg';
      entry.audioUri = 'data:$mime;base64,${base64Encode(audio.bytes)}';
    } else {
      final cachePath = await _ttsCachePath(index, audio.format);
      await File(cachePath).writeAsBytes(audio.bytes);
      entry.audioUri = cachePath;
    }

    entry.audioReceived = true;
    entry.isLoading = false;
    _cache[index] = entry;
  }

  Future<_OfflineBundle?> _loadOfflineBundle(String novel, int chapter) async {
    final result = await offlineContentService.getOfflineChapterAudio(
      novel,
      chapter,
    );
    if (result == null) return null;
    return _OfflineBundle(
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
    Timer(const Duration(milliseconds: 1), () {
      _pumpPreload();
      _cleanupCache(currentIndex);
    });
  }

  /// Keep [AudioCacheConfig.preloadCharacterThreshold] characters of *upcoming*
  /// audio (paragraphs after [_preloadAnchor], not counting it) ready or being
  /// generated. On-device synthesis is serial, so this starts at most one new
  /// generation per call; each completed load re-invokes it, advancing the
  /// buffer until the upcoming-character target is met (or the chapter ends).
  void _pumpPreload() {
    final anchor = _preloadAnchor;
    final paras = _preloadParagraphs;
    if (anchor < 0 || paras.isEmpty) return;

    var bufferedChars = 0;
    var inFlight = false;
    var firstUnstarted = -1;

    for (var i = anchor + 1; i < paras.length; i++) {
      final cached = _cache[i];
      final ready = cached != null && cached.isValid;
      final loading =
          _activeRequests.containsKey(i) || (cached != null && cached.isLoading);
      if (ready || loading) {
        bufferedChars += paras[i].length;
        if (loading) inFlight = true;
      } else if (firstUnstarted < 0) {
        firstUnstarted = i;
      }
      // Enough upcoming audio is ready or already generating — stop.
      if (bufferedChars >= _config.preloadCharacterThreshold) return;
    }

    // Under target and nothing generating → start the next un-started paragraph.
    if (!inFlight && firstUnstarted >= 0) {
      _loadAudioForParagraph(firstUnstarted, paras[firstUnstarted]);
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

    final toDelete = <int>[];
    final filesToDelete = <String>[];

    _cache.forEach((index, data) {
      if (index < keepStart || index > keepEnd) {
        toDelete.add(index);
        if (data.audioUri != null) filesToDelete.add(data.audioUri!);
      }
    });

    for (final i in toDelete) {
      _cache.remove(i);
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
  final String? titleAudio;
  final List<String?> paragraphAudios;
  final int paragraphCount;
  _OfflineBundle({
    required this.titleAudio,
    required this.paragraphAudios,
    required this.paragraphCount,
  });
}
