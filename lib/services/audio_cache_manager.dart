import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/paragraph_audio.dart';
import 'offline_content_service.dart';
import 'tts_api.dart';

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
  double _currentSpeed = 1.0;
  final AudioCacheConfig _config;

  String? _currentNovelName;
  int? _currentChapterNumber;

  _OfflineBundle? _offlineCache;

  AudioCacheManager({
    required String narratorVoice,
    required String dialogueVoice,
    AudioCacheConfig config = const AudioCacheConfig(),
  })  : _narratorVoice = narratorVoice,
        _dialogueVoice = dialogueVoice,
        _config = config;

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
    _currentSpeed = speed;
  }

  /// Update voices. Clears the cache when voices actually change.
  Future<void> updateVoices(String narrator, String dialogue) async {
    if (_narratorVoice == narrator && _dialogueVoice == dialogue) return;
    _narratorVoice = narrator;
    _dialogueVoice = dialogue;
    await clearCache();
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

  /// Forcefully preload up to `count` paragraphs ahead. Called on app pause.
  void preloadAhead(int currentIndex, List<String> allParagraphs,
      {int count = 15}) {
    for (var i = currentIndex + 1;
        i < allParagraphs.length && i <= currentIndex + count;
        i++) {
      if (!_cache.containsKey(i) && !_activeRequests.containsKey(i)) {
        _loadAudioForParagraph(i, allParagraphs[i]);
      }
    }
  }

  Future<void> clearCache() async {
    final files = _cache.values
        .where((v) => v.audioUri != null)
        .map((v) => v.audioUri!)
        .toList();
    _cache.clear();
    _activeRequests.clear();
    _offlineCache = null;
    for (final path in files) {
      try {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
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
    }
  }

  Future<void> _loadInternal(
    int index,
    String text,
    ParagraphAudioData entry,
  ) async {
    // 1. Offline-first lookup
    if (_currentNovelName != null && _currentChapterNumber != null) {
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

    // 2. TTS API
    final bytes = await ttsApi.convertDualVoice(
      text: text,
      paragraphVoice: _narratorVoice,
      dialogueVoice: _dialogueVoice,
    );

    final cachePath = await _ttsCachePath(index);
    final file = File(cachePath);
    await file.writeAsBytes(bytes);

    entry.audioReceived = true;
    entry.audioUri = cachePath;
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

  Future<String> _ttsCachePath(int index) async {
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, 'audio_cache'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return p.join(
      dir.path,
      'audio_${index}_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
  }

  // ---- Preload engine ----

  void _triggerPreload(int currentIndex, List<String> allParagraphs) {
    final speed = _currentSpeed;
    final delayMs = speed >= 1.5 ? 0 : 1;
    Timer(Duration(milliseconds: delayMs), () async {
      try {
        // Ultra-priority: immediate next paragraph.
        final nextIndex = currentIndex + 1;
        if (nextIndex < allParagraphs.length &&
            !_cache.containsKey(nextIndex) &&
            !_activeRequests.containsKey(nextIndex)) {
          _loadAudioForParagraph(nextIndex, allParagraphs[nextIndex]);
        }

        var totalChars = 0;
        var preloadCount = 0;

        final speedMultiplier = min(speed, 2.5);
        final adaptiveMax = min(
          (_config.maxPreloadDistance * speedMultiplier).floor(),
          allParagraphs.length - currentIndex - 1,
        );

        for (var i = currentIndex + 1;
            i < allParagraphs.length && preloadCount < adaptiveMax;
            i++) {
          final paragraph = allParagraphs[i];
          totalChars += paragraph.length;
          preloadCount++;

          if (!_cache.containsKey(i) && !_activeRequests.containsKey(i)) {
            _loadAudioForParagraph(i, paragraph);
          }

          if (totalChars >= _config.preloadCharacterThreshold) break;
        }

        _cleanupCache(currentIndex);
      } catch (_) {}
    });
  }

  void _cleanupCache(int currentIndex) {
    if (_cache.length <= _config.maxCacheSize) return;

    const keepBefore = 3;
    final keepStart = max(0, currentIndex - keepBefore);
    final keepEnd = currentIndex + _config.maxPreloadDistance;

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
