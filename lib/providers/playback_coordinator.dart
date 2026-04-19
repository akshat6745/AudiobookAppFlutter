import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chapter.dart';
import '../models/novel.dart';
import '../services/audio_handler.dart';
import '../services/chapter_api.dart';
import '../services/novel_api.dart';
import '../services/offline_content_service.dart';
import 'audio_providers.dart';
import 'last_position_provider.dart';
import 'progress_providers.dart';

/// Coordinates high-level playback operations: loading a chapter, playing
/// a paragraph, auto-advancing, and loading the next chapter on completion.
///
/// Equivalent of the RN app's AudioContext but without state masking — the
/// underlying handler's own stream is the source of truth for isPlaying /
/// processingState, and this coordinator only persists high-level state.
class PlaybackCoordinator {
  PlaybackCoordinator(this._ref) {
    _wireCallbacks();
  }

  final Ref _ref;

  AudiobookHandler get _handler => _ref.read(audioHandlerProvider);

  void _wireCallbacks() {
    _handler.setCallbacks(
      AudiobookCallbacks(
        onAutoAdvance: _onAutoAdvance,
        onRemoteNext: _onRemoteNext,
        onRemotePrevious: _onRemotePrevious,
      ),
    );
  }

  // ---- Chapter loading ----

  Future<void> loadChapter({
    required Novel novel,
    required Chapter chapter,
    List<String>? initialContent,
    bool autoPlay = false,
  }) async {
    List<String> content;
    if (initialContent != null && initialContent.isNotEmpty) {
      content = initialContent;
    } else {
      // Offline-first: try downloaded content before network.
      final offline = await offlineContentService.getOfflineChapterContent(
        novel.slug,
        chapter.chapterNumber,
      );
      if (offline != null) {
        content = offline.content;
      } else {
        final remote = await chapterApi.getChapterContent(
          chapterNumber: chapter.chapterNumber,
          novelSlug: novel.slug,
        );
        content = remote.content;
      }
    }

    // Client-side convention: content[0] is the chapter title.
    final titleLine = 'Chapter ${chapter.chapterNumber}: ${chapter.chapterTitle}';
    final prepared = [titleLine, ...content];

    _ref.read(audioStateProvider.notifier).loadChapter(
          novel: novel,
          chapter: chapter,
          content: prepared,
        );

    // Prepare cache + handler context.
    final cache = _ref.read(audioCacheProvider);
    cache.setContext(novel.slug, chapter.chapterNumber);
    _handler.setParagraphs(prepared);
    await _handler.setMetadata(
      novelName: novel.title,
      chapterTitle: titleLine,
      artworkUri: novelApi.coverUrl(novel.slug),
    );

    // Persist progress
    _ref.read(progressProvider.notifier).updateProgress(
          novel.slug,
          chapter.chapterNumber,
        );

    if (autoPlay && prepared.isNotEmpty) {
      await playParagraph(0);
    }
  }

  // ---- Playback ----

  Future<void> playParagraph(int index) async {
    final audio = _ref.read(audioStateProvider);
    if (index < 0 || index >= audio.content.length) return;

    _ref.read(audioStateProvider.notifier).setCurrentIndex(index);
    _ref.read(audioStateProvider.notifier).setIsLoading(true);

    final novel = audio.novel;
    final chapter = audio.chapter;
    if (novel != null && chapter != null) {
      _ref.read(lastPositionProvider.notifier).update(
            novelSlug: novel.slug,
            chapter: chapter.chapterNumber,
            paragraph: index,
            preview: audio.content[index],
          );
    }

    final ok = await _handler.playParagraph(
      paragraphIndex: index,
      paragraphText: audio.content[index],
    );

    _ref.read(audioStateProvider.notifier).setIsLoading(false);
    _ref.read(audioStateProvider.notifier).setIsPlaying(ok);
  }

  Future<void> toggle() async {
    await _handler.toggle();
    final playing = _ref.read(audioStateProvider).isPlaying;
    _ref.read(audioStateProvider.notifier).setIsPlaying(!playing);
  }

  Future<void> setSpeed(double speed) async {
    await _handler.setSpeed(speed);
    _ref.read(audioStateProvider.notifier).setSpeed(speed);
  }

  Future<void> playNext() async {
    final s = _ref.read(audioStateProvider);
    final idx = s.currentIndex;
    if (idx == null) return;
    final next = idx + 1;
    if (next >= s.content.length) {
      await _loadAndPlayNextChapter();
    } else {
      await playParagraph(next);
    }
  }

  Future<void> playPrevious() async {
    final s = _ref.read(audioStateProvider);
    final idx = s.currentIndex;
    if (idx == null || idx <= 0) return;
    await playParagraph(idx - 1);
  }

  // ---- Callbacks from handler ----

  Future<bool> _onAutoAdvance(int from, int to) async {
    final s = _ref.read(audioStateProvider);
    if (to >= s.content.length) {
      await _loadAndPlayNextChapter();
      return true;
    }
    await playParagraph(to);
    return true;
  }

  Future<void> _onRemoteNext() => playNext();
  Future<void> _onRemotePrevious() => playPrevious();

  Future<void> _loadAndPlayNextChapter() async {
    final s = _ref.read(audioStateProvider);
    final novel = s.novel;
    final chapter = s.chapter;
    if (novel == null || chapter == null) return;
    try {
      final next = Chapter(
        chapterNumber: chapter.chapterNumber + 1,
        chapterTitle: 'Chapter ${chapter.chapterNumber + 1}',
      );
      await loadChapter(novel: novel, chapter: next, autoPlay: true);
    } catch (_) {
      // End of book or fetch error — stop playback.
      _ref.read(audioStateProvider.notifier).setIsPlaying(false);
    }
  }
}

final playbackCoordinatorProvider = Provider<PlaybackCoordinator>(
  (ref) => PlaybackCoordinator(ref),
);
