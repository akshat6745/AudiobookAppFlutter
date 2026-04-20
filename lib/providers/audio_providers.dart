import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chapter.dart';
import '../models/novel.dart';
import '../services/audio_cache_manager.dart';
import '../services/audio_handler.dart';

/// Voice preferences (defaults match RN app).
final narratorVoiceProvider =
    StateProvider<String>((_) => 'en-US-AvaMultilingualNeural');
final dialogueVoiceProvider =
    StateProvider<String>((_) => 'en-GB-RyanNeural');

final audioCacheProvider = Provider<AudioCacheManager>((ref) {
  final narrator = ref.watch(narratorVoiceProvider);
  final dialogue = ref.watch(dialogueVoiceProvider);
  return AudioCacheManager(
    narratorVoice: narrator,
    dialogueVoice: dialogue,
  );
});

/// AudioHandler is injected from main.dart after AudioService.init().
final audioHandlerProvider = Provider<AudiobookHandler>((ref) {
  throw UnimplementedError(
    'audioHandlerProvider must be overridden in ProviderScope.',
  );
});

/// Simple observable state (mirrors what UI needs).
class AudioState {
  final bool isPlaying;
  final bool isLoading;
  final int? currentIndex;
  final Novel? novel;
  final Chapter? chapter;
  final List<String> content;
  final double playbackSpeed;

  const AudioState({
    this.isPlaying = false,
    this.isLoading = false,
    this.currentIndex,
    this.novel,
    this.chapter,
    this.content = const [],
    this.playbackSpeed = 1.0,
  });

  AudioState copyWith({
    bool? isPlaying,
    bool? isLoading,
    int? currentIndex,
    Novel? novel,
    Chapter? chapter,
    List<String>? content,
    double? playbackSpeed,
  }) =>
      AudioState(
        isPlaying: isPlaying ?? this.isPlaying,
        isLoading: isLoading ?? this.isLoading,
        currentIndex: currentIndex ?? this.currentIndex,
        novel: novel ?? this.novel,
        chapter: chapter ?? this.chapter,
        content: content ?? this.content,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      );
}

class AudioStateNotifier extends StateNotifier<AudioState> {
  AudioStateNotifier() : super(const AudioState());

  void setIsPlaying(bool value) => state = state.copyWith(isPlaying: value);

  void setIsLoading(bool value) => state = state.copyWith(isLoading: value);

  void setCurrentIndex(int? index) =>
      state = state.copyWith(currentIndex: index);

  void setSpeed(double s) => state = state.copyWith(playbackSpeed: s);

  void loadChapter({
    required Novel novel,
    required Chapter chapter,
    required List<String> content,
  }) {
    state = state.copyWith(
      novel: novel,
      chapter: chapter,
      content: content,
      currentIndex: null,
      isPlaying: false,
    );
  }

  void reset() => state = const AudioState();
}

final audioStateProvider =
    StateNotifierProvider<AudioStateNotifier, AudioState>(
  (_) => AudioStateNotifier(),
);
