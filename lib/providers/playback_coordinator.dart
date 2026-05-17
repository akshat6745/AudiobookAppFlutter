import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chapter.dart';
import '../models/novel.dart';
import '../services/audio_handler.dart';
import '../services/chapter_api.dart';
import '../services/novel_api.dart';
import '../services/offline_content_service.dart';
import '../widget/audiobook_home_widget.dart';
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
    // Push widget updates whenever the player transitions play/pause —
    // catches MediaSession-driven changes that don't go through this class.
    _playbackSub = _handler.playbackState.listen(_onHandlerPlayback);
  }

  final Ref _ref;
  StreamSubscription<PlaybackState>? _playbackSub;
  DateTime? _lastProgressRefreshAt;

  AudiobookHandler get _handler => _ref.read(audioHandlerProvider);

  void _wireCallbacks() {
    _handler.setCallbacks(
      AudiobookCallbacks(
        onAutoAdvance: _onAutoAdvance,
        onRemoteNext: _onRemoteNext,
        onRemotePrevious: _onRemotePrevious,
        onRemoteStop: _onRemoteStop,
      ),
    );
  }

  void _onHandlerPlayback(PlaybackState ps) {
    _pushWidgetState();
    // Throttled progress refresh on play transitions — the user may have
    // listened on another device since we last fetched, so we want fresh
    // server state to surface in the chapter/novel list. Throttle to 30s
    // so background buffering events don't trigger a flood of requests.
    if (ps.playing) {
      final now = DateTime.now();
      final last = _lastProgressRefreshAt;
      if (last == null || now.difference(last) > const Duration(seconds: 30)) {
        _lastProgressRefreshAt = now;
        _ref.read(progressProvider.notifier).refresh();
      }
    }
  }

  void _pushWidgetState() {
    final s = _ref.read(audioStateProvider);
    final idx = s.currentIndex;
    final paragraph = (idx != null && idx < s.content.length)
        ? s.content[idx]
        : '';
    // Use the handler's playbackState as the source of truth for isPlaying —
    // audioStateProvider lags behind when media buttons (widget/notification)
    // trigger play/pause directly on the handler.
    final handlerPlaying =
        _handler.playbackState.valueOrNull?.playing ?? s.isPlaying;
    AudiobookHomeWidget.updateState(
      novelTitle: s.novel?.title ?? '',
      chapterTitle: s.chapter?.chapterTitle ?? '',
      paragraphText: paragraph,
      isPlaying: handlerPlaying,
      speed: s.playbackSpeed,
    );
  }

  void dispose() {
    _playbackSub?.cancel();
  }

  // ---- Chapter loading ----

  /// Load a chapter into the audio state. Used when starting playback for
  /// a chapter we aren't already playing (tap-to-play, auto-advance).
  ///
  /// Idempotent: if the chapter is already loaded with the same novel, this
  /// returns early without resetting `currentIndex` so an in-progress
  /// playback keeps its highlight.
  Future<void> loadChapter({
    required Novel novel,
    required Chapter chapter,
    List<String>? initialContent,
    bool autoPlay = false,
  }) async {
    final current = _ref.read(audioStateProvider);
    final alreadyLoaded = current.novel?.slug == novel.slug &&
        current.chapter?.chapterNumber == chapter.chapterNumber &&
        current.content.isNotEmpty;

    List<String> prepared;
    if (alreadyLoaded) {
      prepared = current.content;
    } else {
      final content = initialContent ?? await _resolveContent(novel, chapter);
      // Client-side convention: content[0] is the chapter title.
      final titleLine = 'Chapter ${chapter.chapterNumber}: ${chapter.chapterTitle}';
      prepared = [titleLine, ...content];

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

      // Persist progress (optimistic, server reconciles on next refresh).
      _ref.read(progressProvider.notifier).updateProgress(
            novel.slug,
            chapter.chapterNumber,
          );
    }

    _pushWidgetState();

    if (autoPlay && prepared.isNotEmpty) {
      await playParagraph(0);
    }
  }

  /// Atomic "play this paragraph in this chapter" operation. Used by the
  /// reader screen so taps don't race with chapter loading — guarantees
  /// the audio state matches the user's intended chapter before playback
  /// starts. Pass `content` if the screen already has it loaded (avoids
  /// a redundant network round-trip).
  Future<void> playChapterParagraph({
    required Novel novel,
    required Chapter chapter,
    required int paragraphIndex,
    List<String>? content,
  }) async {
    await loadChapter(
      novel: novel,
      chapter: chapter,
      initialContent: content,
    );
    await playParagraph(paragraphIndex);
  }

  Future<List<String>> _resolveContent(Novel novel, Chapter chapter) async {
    // Offline-first: try downloaded content before network.
    final offline = await offlineContentService.getOfflineChapterContent(
      novel.slug,
      chapter.chapterNumber,
    );
    if (offline != null) return offline.content;
    final remote = await chapterApi.getChapterContent(
      chapterNumber: chapter.chapterNumber,
      novelSlug: novel.slug,
    );
    return remote.content;
  }

  // ---- Playback ----

  Future<void> playParagraph(int index) async {
    final audio = _ref.read(audioStateProvider);
    if (index < 0 || index >= audio.content.length) return;

    // Silence current audio immediately so the user doesn't hear the old
    // paragraph while the new one loads. Use pause (not stop) to avoid
    // tearing down the MediaSession.
    await _handler.pause();

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
    _pushWidgetState();
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

  /// Fully stop playback and reset audio state. Clears the MediaSession,
  /// dismisses the notification (handled in [AudiobookHandler.stop]), and
  /// resets the UI-facing audio state so the mini-player and any
  /// paragraph highlights disappear.
  Future<void> stop() async {
    await _handler.stopFromCoordinator();
    _ref.read(audioStateProvider.notifier).reset();
    // Push an empty widget state so the home-screen widget shows nothing
    // playing instead of a stale paragraph.
    AudiobookHomeWidget.updateState(
      novelTitle: '',
      chapterTitle: '',
      paragraphText: '',
      isPlaying: false,
      speed: 1.0,
    );
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
  Future<void> _onRemoteStop() => stop();

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
