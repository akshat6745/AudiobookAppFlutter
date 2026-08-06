import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_cache_manager.dart';

/// Callback contract used by the UI / providers layer.
/// These are fired by the handler at key state transitions.
class AudiobookCallbacks {
  /// Called when a paragraph finishes and we should load the next one.
  /// If the returned bool is false, playback stops (end of chapter etc.).
  final Future<bool> Function(int fromIndex, int toIndex)? onAutoAdvance;

  /// Called when the "next" media action is triggered (from notification, etc.)
  final Future<void> Function()? onRemoteNext;

  /// Called when the "previous" media action is triggered.
  final Future<void> Function()? onRemotePrevious;

  /// Called when the OS stop control (notification swipe / remote stop)
  /// is invoked. Coordinator should reset UI state to match.
  final Future<void> Function()? onRemoteStop;

  const AudiobookCallbacks({
    this.onAutoAdvance,
    this.onRemoteNext,
    this.onRemotePrevious,
    this.onRemoteStop,
  });
}

/// Single source of truth for playback. Drives just_audio and publishes
/// MediaSession state via audio_service.
class AudiobookHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final AudioCacheManager cache;

  List<String> _paragraphs = const [];
  int? _currentIndex;

  String _novelName = '';
  String _chapterTitle = '';
  String? _artworkUri;

  double _playbackSpeed = 1.0;
  bool _rateApplied = false;

  AudiobookCallbacks _callbacks = const AudiobookCallbacks();

  /// Guards against multiple completion triggers for the same paragraph.
  int? _lastCompletedIndex;

  /// Bumped by [setParagraphs] (new chapter loaded) and [stop]. [playParagraph]
  /// captures this on entry and re-checks it after every `await` — a mismatch
  /// means a chapter switch (or stop) happened while this call was in flight,
  /// so its result is discarded instead of being played. This is what stops
  /// audio from a stale request ever reaching the player.
  int _generation = 0;

  /// Re-entrancy guard for [stop] — when the coordinator initiates a stop
  /// it sets this so the handler doesn't fire `onRemoteStop` back into the
  /// coordinator (which would loop).
  bool _suppressRemoteStop = false;

  AudiobookHandler({required this.cache}) {
    _wireStreams();
  }

  // ---- Public API ----

  Future<void> setMetadata({
    required String novelName,
    required String chapterTitle,
    String? artworkUri,
  }) async {
    _novelName = novelName;
    _chapterTitle = chapterTitle;
    _artworkUri = artworkUri;
  }

  void setCallbacks(AudiobookCallbacks callbacks) {
    _callbacks = callbacks;
  }

  /// Called whenever the coordinator loads a (new) chapter's paragraphs.
  /// Starts a new playback session: bumps the generation and atomically
  /// resets the index/completion state so a stale auto-advance or in-flight
  /// [playParagraph] call from the previous chapter can never act on the new
  /// one.
  void setParagraphs(List<String> paragraphs) {
    _generation++;
    _paragraphs = paragraphs;
    _currentIndex = null;
    _lastCompletedIndex = null;
  }

  int? get currentIndex => _currentIndex;
  double get playbackSpeed => _playbackSpeed;

  /// Play a specific paragraph. Resolves audio via the cache manager then
  /// swaps the just_audio source.
  ///
  /// Session-safe: captures the current generation and the requested index
  /// up front, then re-validates both after every `await`. If a chapter
  /// switch happened ([setParagraphs]/[stop] bumped the generation) or a
  /// newer `playParagraph` call has since taken over `_currentIndex` while
  /// this call was awaiting, it bails out without touching the player —
  /// the most recent request always wins, and a late-resolving stale one
  /// can never play its audio over the current session.
  Future<bool> playParagraph({
    required int paragraphIndex,
    required String paragraphText,
  }) async {
    final gen = _generation;
    try {
      _currentIndex = paragraphIndex;
      _lastCompletedIndex = null;
      _emitPlaybackState(isLoading: true);

      final audio = await cache.getAudio(
        paragraphIndex: paragraphIndex,
        paragraphText: paragraphText,
        allParagraphs: _paragraphs,
      );

      if (!_isCurrent(gen, paragraphIndex)) return false;

      if (audio == null || !audio.isValid) {
        _emitPlaybackState(isLoading: false);
        return false;
      }

      final preview = paragraphText.length > 120
          ? '${paragraphText.substring(0, 120)}...'
          : paragraphText;

      final audioUri = audio.audioUri!;
      final mediaItem = MediaItem(
        id: 'paragraph_${audio.paragraphIndex}',
        title: _chapterTitle.isNotEmpty
            ? _chapterTitle
            : 'Paragraph ${audio.paragraphIndex + 1}',
        artist: preview,
        album: _novelName.isNotEmpty ? _novelName : 'Audiobook Reader',
        artUri: _artworkUri != null ? Uri.parse(_artworkUri!) : null,
        duration: audio.duration,
      );

      // Use AudioSource.uri so the same code path handles local file paths
      // (mobile/desktop) and data:/http: URIs (web).
      final uri = (audioUri.startsWith('data:') || audioUri.startsWith('http'))
          ? Uri.parse(audioUri)
          : Uri.file(audioUri);
      await _player.setAudioSource(AudioSource.uri(uri));

      if (!_isCurrent(gen, paragraphIndex)) return false;

      this.mediaItem.add(mediaItem);

      if (!_rateApplied) {
        await _player.setSpeed(_playbackSpeed);
        _rateApplied = true;
      }

      if (!_isCurrent(gen, paragraphIndex)) return false;

      cache.setCurrentlyPlaying(paragraphIndex);
      await _player.play();
      return true;
    } catch (_) {
      _emitPlaybackState(isLoading: false);
      return false;
    }
  }

  /// Whether [gen]/[paragraphIndex] still describe the session and request
  /// this call was made for — false means a newer chapter or a newer
  /// `playParagraph` call has since taken over.
  bool _isCurrent(int gen, int paragraphIndex) =>
      gen == _generation && _currentIndex == paragraphIndex;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    // Track whether this stop originated from a remote/notification action
    // so we can fire the coordinator callback exactly once.
    final wasActive = _currentIndex != null;
    // Reset state up-front so any in-flight stream events — or a
    // `playParagraph` call already in flight — don't re-trigger auto-advance
    // or a stale play against an index/session that no longer exists.
    _generation++;
    _currentIndex = null;
    _lastCompletedIndex = null;
    _paragraphs = const [];
    await _player.stop();
    // Drop the current MediaItem so the OS notification / lock-screen
    // controls can be dismissed cleanly.
    mediaItem.add(null);
    // Push an explicit idle state so platform UI (notification, widget,
    // mini-player StreamBuilders) all flip to "not playing" immediately.
    playbackState.add(
      PlaybackState(
        controls: const [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        speed: _playbackSpeed,
      ),
    );
    await super.stop();

    // Notify the coordinator if this came from outside (notification stop,
    // remote command). The coordinator uses this to reset the UI-facing
    // audio state. Guarded by `wasActive` and `_suppressRemoteStop` so
    // coordinator-initiated stops don't loop back into themselves.
    if (wasActive &&
        !_suppressRemoteStop &&
        _callbacks.onRemoteStop != null) {
      await _callbacks.onRemoteStop!();
    }
  }

  /// Coordinator-driven stop. Skips the `onRemoteStop` callback (the
  /// coordinator already knows it initiated the stop). Use this from the
  /// app's UI/coordinator path; reserve [stop] for OS / notification
  /// triggers where we need to bubble the event back up.
  Future<void> stopFromCoordinator() async {
    _suppressRemoteStop = true;
    try {
      await stop();
    } finally {
      _suppressRemoteStop = false;
    }
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_callbacks.onRemoteNext != null) {
      await _callbacks.onRemoteNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_callbacks.onRemotePrevious != null) {
      await _callbacks.onRemotePrevious!();
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    final clamped = speed.clamp(0.25, 4.0);
    _playbackSpeed = clamped;
    cache.setPlaybackSpeed(clamped);
    await _player.setSpeed(clamped);
    _rateApplied = true;
    _emitPlaybackState();
  }

  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> disposeHandler() async {
    await _player.dispose();
  }

  // ---- Internals ----

  void _wireStreams() {
    // Playback state feedback to audio_service.
    _player.playerStateStream.listen(_onPlayerStateChanged);
    _player.playbackEventStream.listen((e) => _emitPlaybackState());
  }

  Future<void> _onPlayerStateChanged(PlayerState state) async {
    _emitPlaybackState();

    // Auto-advance trigger. just_audio fires processingState == completed
    // reliably on both Android (ExoPlayer) and iOS (AVAudioPlayer) — no
    // polling workaround needed.
    if (state.processingState == ProcessingState.completed &&
        _currentIndex != null &&
        _lastCompletedIndex != _currentIndex) {
      _lastCompletedIndex = _currentIndex;
      final fromIndex = _currentIndex!;
      final toIndex = fromIndex + 1;
      if (_callbacks.onAutoAdvance != null) {
        await _callbacks.onAutoAdvance!(fromIndex, toIndex);
      }
    }
  }

  void _emitPlaybackState({bool? isLoading}) {
    final playing = _player.playing;
    final processingState = _player.processingState;
    final bufferedPosition = _player.bufferedPosition;
    final position = _player.position;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _mapProcessingState(processingState, isLoading),
        playing: playing,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: _playbackSpeed,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(
    ProcessingState s,
    bool? forcedLoading,
  ) {
    if (forcedLoading == true) return AudioProcessingState.loading;
    switch (s) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
      case ProcessingState.buffering:
        return AudioProcessingState.loading;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}
