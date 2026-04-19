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

  const AudiobookCallbacks({
    this.onAutoAdvance,
    this.onRemoteNext,
    this.onRemotePrevious,
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

  void setParagraphs(List<String> paragraphs) {
    _paragraphs = paragraphs;
  }

  int? get currentIndex => _currentIndex;
  double get playbackSpeed => _playbackSpeed;

  /// Play a specific paragraph. Resolves audio via the cache manager then
  /// swaps the just_audio source. Idempotent-ish: calling with the same index
  /// while it's still loading will early-return.
  Future<bool> playParagraph({
    required int paragraphIndex,
    required String paragraphText,
  }) async {
    try {
      _currentIndex = paragraphIndex;
      _lastCompletedIndex = null;
      _emitPlaybackState(isLoading: true);

      final audio = await cache.getAudio(
        paragraphIndex: paragraphIndex,
        paragraphText: paragraphText,
        allParagraphs: _paragraphs,
      );

      if (audio == null || !audio.isValid) {
        _emitPlaybackState(isLoading: false);
        return false;
      }

      final preview = paragraphText.length > 120
          ? '${paragraphText.substring(0, 120)}...'
          : paragraphText;

      final mediaItem = MediaItem(
        id: audio.audioUri!,
        title: _chapterTitle.isNotEmpty
            ? _chapterTitle
            : 'Paragraph ${audio.paragraphIndex + 1}',
        artist: preview,
        album: _novelName.isNotEmpty ? _novelName : 'Audiobook Reader',
        artUri: _artworkUri != null ? Uri.parse(_artworkUri!) : null,
        duration: audio.duration,
      );
      this.mediaItem.add(mediaItem);

      await _player.setFilePath(audio.audioUri!);

      if (!_rateApplied) {
        await _player.setSpeed(_playbackSpeed);
        _rateApplied = true;
      }

      cache.setCurrentlyPlaying(paragraphIndex);
      await _player.play();
      return true;
    } catch (_) {
      _emitPlaybackState(isLoading: false);
      return false;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
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
