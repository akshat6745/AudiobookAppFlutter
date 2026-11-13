import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:just_audio/just_audio.dart';

import 'audio_cache_manager.dart';

/// What to do when a transient ([AudioInterruptionType.pause]) interruption
/// ends.
enum InterruptionResumeDecision { resume, advance, ignore }

/// Threshold under which a paused paragraph is considered effectively finished
/// (since paragraphs include 250–550ms of trailing silence and hardware/A2DP
/// buffers look ahead by ~300–500ms).
const Duration kNearParagraphEndThreshold = Duration(seconds: 1);

/// True when playback has progressed past the midpoint of the clip and has at
/// most [kNearParagraphEndThreshold] remaining. A clip sitting at
/// [Duration.zero] (e.g. newly loaded during an interruption) is never near
/// its end, even if the clip itself is under 1 second long.
@visibleForTesting
bool isNearParagraphEnd({
  required Duration position,
  required Duration? duration,
}) {
  if (duration == null || duration <= Duration.zero) return false;
  if (position <= Duration.zero) return false;
  if (position * 2 < duration) return false;
  return (duration - position) <= kNearParagraphEndThreshold;
}

/// Decides how to resume when a transient interruption ends.
///
/// Keyed on *intent* ([wantsPlayback]) rather than the player's momentary
/// `playing` flag, because an interruption often lands between paragraphs —
/// while the next one is being synthesized the player is deliberately paused,
/// yet the user still expects narration to continue afterwards.
///
/// - Not wanting playback (user paused, before or during the interruption)
///   → stay paused.
/// - A paragraph load is still in flight → do nothing here; that load starts
///   playback itself once it completes, now that the interruption is over.
///   (Advancing here would skip the paragraph being loaded.)
/// - The source already finished or is within [kNearParagraphEndThreshold] of
///   the end → take the normal auto-advance path so playback does not get
///   stuck on a completed/silent tail.
/// - Otherwise → resume the loaded source.
@visibleForTesting
InterruptionResumeDecision decideInterruptionResume({
  required bool wantsPlayback,
  required bool loadInFlight,
  required ProcessingState processingState,
  Duration position = Duration.zero,
  Duration? duration,
}) {
  if (!wantsPlayback || loadInFlight) return InterruptionResumeDecision.ignore;
  if (processingState == ProcessingState.completed ||
      isNearParagraphEnd(position: position, duration: duration)) {
    return InterruptionResumeDecision.advance;
  }
  return InterruptionResumeDecision.resume;
}

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
  /// just_audio's built-in interruption handling is disabled: it keeps its
  /// own "was playing" flag that knows nothing about paragraph transitions,
  /// and running it alongside [_onInterruption] made the two fight (each
  /// pausing/resuming on different state). This handler is the sole owner.
  final AudioPlayer _player = AudioPlayer(handleInterruptions: false);
  final AudioCacheManager cache;

  List<String> _paragraphs = const [];
  int? _currentIndex;
  int? _loadedIndex;

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

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;

  /// Set while we've ducked the volume for an [AudioInterruptionType.duck]
  /// interruption (e.g. a notification chime), so we know to restore it —
  /// and only it, not a user-chosen volume — when the interruption ends.
  bool _duckedByInterruption = false;

  /// Whether narration *should* be playing — true from a play request
  /// ([playParagraph], [play]) until the user pauses/stops or a load fails.
  /// Unlike `_player.playing`, this stays true across the deliberate pause
  /// between paragraphs, so an interruption that lands during a paragraph
  /// transition still resumes afterwards; a manual pause clears it so the
  /// interruption ending never overrides the user.
  bool _wantsPlayback = false;

  /// Set while a transient interruption ([AudioInterruptionType.pause], e.g.
  /// a phone call or notification sound) is in progress. Blocks
  /// [playParagraph] from starting playback mid-interruption — the loaded
  /// paragraph waits and plays when the interruption ends.
  bool _transientInterruption = false;

  /// Number of [playParagraph] calls currently resolving audio / loading the
  /// source.
  int _loadsInFlight = 0;

  AudiobookHandler({required this.cache}) {
    _wireStreams();
    _wireAudioSessionEvents();
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
    _loadedIndex = null;
    _lastCompletedIndex = null;
  }

  int? get currentIndex => _currentIndex;
  double get playbackSpeed => _playbackSpeed;
  bool get wantsPlayback => _wantsPlayback;

  /// Whether the player is actively producing sound (excludes the post-EOF
  /// state where just_audio keeps `playing == true` at `completed`).
  bool get _isEffectivelyPlaying =>
      _player.playing && _player.processingState != ProcessingState.completed;

  /// True when audio is actively playing or a paragraph load is in flight
  /// that intends to play as soon as it finishes.
  bool get _shouldPauseOnToggle =>
      _isEffectivelyPlaying ||
      (_loadsInFlight > 0 && _wantsPlayback && !_transientInterruption);

  /// Silences the player before loading a new chapter/paragraph without
  /// clearing [_wantsPlayback], so auto-advance and in-flight interruptions
  /// never mistake an internal transition for a manual user pause.
  Future<void> pauseForTransition() => _player.pause();

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
    _loadsInFlight++;
    try {
      _currentIndex = paragraphIndex;
      _lastCompletedIndex = null;
      _wantsPlayback = true;
      _emitPlaybackState(isLoading: true);

      // Silence whatever is currently playing without clearing _wantsPlayback.
      await _player.pause();
      if (!_isCurrent(gen, paragraphIndex)) return false;

      final audio = await cache.getAudio(
        paragraphIndex: paragraphIndex,
        paragraphText: paragraphText,
        allParagraphs: _paragraphs,
      );

      if (!_isCurrent(gen, paragraphIndex)) return false;

      if (audio == null || !audio.isValid) {
        _wantsPlayback = false;
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
      _loadedIndex = null;
      await _player.setAudioSource(AudioSource.uri(uri));

      if (!_isCurrent(gen, paragraphIndex)) return false;
      _loadedIndex = paragraphIndex;

      this.mediaItem.add(mediaItem);

      if (!_rateApplied) {
        await _player.setSpeed(_playbackSpeed);
        _rateApplied = true;
      }

      if (!_isCurrent(gen, paragraphIndex)) return false;

      // Mid-interruption (e.g. on a call): keep the paragraph loaded but
      // silent; [_onInterruption] resumes it when the interruption ends.
      // Likewise if the user paused (or headphones were unplugged) while
      // this paragraph was loading.
      if (_transientInterruption || !_wantsPlayback) {
        _emitPlaybackState();
        return _wantsPlayback;
      }

      // Not awaited: just_audio's play() only completes once playback
      // pauses or stops, which would keep this load counted as in flight.
      unawaited(_player.play().catchError((Object _) {}));
      return true;
    } catch (_) {
      if (_isCurrent(gen, paragraphIndex)) _wantsPlayback = false;
      _emitPlaybackState(isLoading: false);
      return false;
    } finally {
      _loadsInFlight--;
    }
  }

  /// Whether [gen]/[paragraphIndex] still describe the session and request
  /// this call was made for — false means a newer chapter or a newer
  /// `playParagraph` call has since taken over.
  bool _isCurrent(int gen, int paragraphIndex) =>
      gen == _generation && _currentIndex == paragraphIndex;

  /// An explicit play request (UI, notification, headset) — the user's
  /// choice overrides any interruption in progress.
  @override
  Future<void> play() async {
    _wantsPlayback = true;
    _transientInterruption = false;

    // 1. If a paragraph load is already in flight (e.g. paused while the next
    //    paragraph was being fetched/synthesized), flipping _wantsPlayback
    //    back to true lets playParagraph() start playback once it finishes.
    if (_loadsInFlight > 0) {
      _emitPlaybackState(isLoading: true);
      return;
    }

    // 2. If _currentIndex was set but its audio hasn't been loaded into
    //    _player yet (e.g. a load failed or was interrupted before
    //    setAudioSource), load and play _currentIndex now.
    if (_currentIndex != null &&
        _currentIndex! < _paragraphs.length &&
        (_loadedIndex != _currentIndex ||
            _player.processingState == ProcessingState.idle)) {
      await playParagraph(
        paragraphIndex: _currentIndex!,
        paragraphText: _paragraphs[_currentIndex!],
      );
      return;
    }

    // 3. If the loaded paragraph already reached completed, or was paused in
    //    its final <=1s (which is mostly trailing silence / A2DP buffer tail),
    //    calling _player.play() would either no-op at STATE_ENDED or play a
    //    brief blip of silence. Advance directly to the next paragraph.
    if (_player.processingState == ProcessingState.completed ||
        isNearParagraphEnd(
          position: _player.position,
          duration: _player.duration,
        )) {
      _lastCompletedIndex = null;
      await _triggerAutoAdvance();
      return;
    }

    _lastCompletedIndex = null;
    // Not awaited: just_audio's play() only completes once playback pauses
    // or stops.
    unawaited(_player.play().catchError((Object _) {}));
  }

  @override
  Future<void> pause() async {
    _wantsPlayback = false;
    await _player.pause();
    _emitPlaybackState();
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        await toggle();
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  @override
  Future<void> stop() async {
    // Track whether this stop originated from a remote/notification action
    // so we can fire the coordinator callback exactly once.
    final wasActive = _currentIndex != null;
    _wantsPlayback = false;
    _transientInterruption = false;
    // Reset state up-front so any in-flight stream events — or a
    // `playParagraph` call already in flight — don't re-trigger auto-advance
    // or a stale play against an index/session that no longer exists.
    _generation++;
    _currentIndex = null;
    _loadedIndex = null;
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
    if (wasActive && !_suppressRemoteStop && _callbacks.onRemoteStop != null) {
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
    await _player.setSpeed(clamped);
    _rateApplied = true;
    _emitPlaybackState();
  }

  Future<void> toggle() async {
    if (_shouldPauseOnToggle) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> disposeHandler() async {
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    await _player.dispose();
  }

  // ---- Internals ----

  void _wireStreams() {
    // Playback state feedback to audio_service.
    _player.playerStateStream.listen(_onPlayerStateChanged);
    _player.playbackEventStream.listen((e) => _emitPlaybackState());
  }

  /// Subscribes to `audio_session`'s interruption + route-change streams.
  /// The session itself is configured once in `main.dart` before this
  /// handler is constructed; here we only react to it. Fire-and-forget from
  /// the constructor is intentional — these are best-effort OS integrations,
  /// not required for the handler to function.
  Future<void> _wireAudioSessionEvents() async {
    final session = await AudioSession.instance;
    _interruptionSub = session.interruptionEventStream.listen(_onInterruption);
    _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
      // Headphones/Bluetooth disconnected — pause immediately so audio
      // doesn't suddenly blast out of the speaker.
      // Also covers the gap while the next paragraph is loading (player
      // paused but [_wantsPlayback] still set), so it doesn't start on the
      // speaker once loaded.
      pause();
    });
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          // Another app needs to be briefly heard (e.g. a nav prompt) —
          // lower volume rather than pausing narration.
          _duckedByInterruption = true;
          _player.setVolume(0.3);
          break;
        case AudioInterruptionType.pause:
          // Transient: phone call, alarm, or a notification sound (the
          // speech session config pauses rather than ducks for those).
          // Android always follows up with an end event.
          _transientInterruption = true;
          _player.pause();
          _emitPlaybackState();
          break;
        case AudioInterruptionType.unknown:
          // iOS: any interruption beginning (its end may still ask us to
          // resume). Android: another app took focus permanently — no end
          // event follows, so the next user play request resumes.
          _transientInterruption = true;
          _player.pause();
          _emitPlaybackState();
          break;
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (_duckedByInterruption) {
            _duckedByInterruption = false;
            _player.setVolume(1.0);
          }
          break;
        case AudioInterruptionType.pause:
          // Android: transient focus regained. iOS: interruption ended
          // with `shouldResume`.
          _transientInterruption = false;
          final decision = decideInterruptionResume(
            wantsPlayback: _wantsPlayback,
            loadInFlight: _loadsInFlight > 0,
            processingState: _player.processingState,
            position: _player.position,
            duration: _player.duration,
          );
          switch (decision) {
            case InterruptionResumeDecision.resume:
              play();
              break;
            case InterruptionResumeDecision.advance:
              _lastCompletedIndex = null;
              _triggerAutoAdvance();
              break;
            case InterruptionResumeDecision.ignore:
              _emitPlaybackState();
              break;
          }
          break;
        case AudioInterruptionType.unknown:
          // iOS ended without `shouldResume` — stay paused.
          _transientInterruption = false;
          _emitPlaybackState();
          break;
      }
    }
  }

  Future<void> _onPlayerStateChanged(PlayerState state) async {
    _emitPlaybackState();

    // Auto-advance trigger. just_audio fires processingState == completed
    // reliably on both Android (ExoPlayer) and iOS (AVAudioPlayer) — no
    // polling workaround needed.
    // Only auto-advance when playback is still wanted and not paused for an
    // interruption; if the last <1s drains into `completed` while paused or
    // interrupted, leave `_lastCompletedIndex` unconsumed so resuming
    // advances cleanly to the next paragraph.
    if (state.processingState == ProcessingState.completed &&
        _wantsPlayback &&
        !_transientInterruption) {
      await _triggerAutoAdvance();
    }
  }

  /// Advances to the next paragraph past [_currentIndex]. Shared by the
  /// natural-completion listener, [play], and the interruption-end handler
  /// (which needs the same path when a paragraph finished during/around an
  /// interruption). Guarded by [_lastCompletedIndex] so it can never fire
  /// twice for the same paragraph.
  Future<void> _triggerAutoAdvance() async {
    if (_currentIndex == null || _lastCompletedIndex == _currentIndex) {
      return;
    }
    _lastCompletedIndex = _currentIndex;
    final fromIndex = _currentIndex!;
    final toIndex = fromIndex + 1;
    if (_callbacks.onAutoAdvance != null) {
      await _callbacks.onAutoAdvance!(fromIndex, toIndex);
    }
  }

  void _emitPlaybackState({bool? isLoading}) {
    final playing = _isEffectivelyPlaying;
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
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
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
