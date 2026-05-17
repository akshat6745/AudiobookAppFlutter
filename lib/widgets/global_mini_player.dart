import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/audio_providers.dart';
import '../providers/playback_coordinator.dart';
import '../router.dart';
import '../theme/app_theme.dart';
import 'now_playing_modal.dart';

class GlobalMiniPlayer extends ConsumerWidget {
  const GlobalMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(audioStateProvider);
    if (audioState.currentIndex == null) return const SizedBox.shrink();

    final handler = ref.watch(audioHandlerProvider);
    final coord = ref.read(playbackCoordinatorProvider);
    final content = audioState.content;
    final index = audioState.currentIndex!;
    final preview = index < content.length ? content[index] : '';

    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          color: AppColors.surfaceDark,
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: StreamBuilder<PlaybackState>(
            stream: handler.playbackState,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Open chapter',
                      icon: const Icon(Icons.menu_book,
                          color: AppColors.primary),
                      onPressed: () => _openChapter(context, audioState),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => showNowPlayingModal(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                audioState.chapter?.chapterTitle ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      onPressed: coord.playPrevious,
                    ),
                    Builder(builder: (_) {
                      final ps = snapshot.data;
                      final loading = ps != null &&
                          !playing &&
                          (ps.processingState ==
                                  AudioProcessingState.loading ||
                              ps.processingState ==
                                  AudioProcessingState.buffering);
                      if (loading) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      }
                      return IconButton(
                        icon: Icon(
                          playing
                              ? Icons.pause_circle
                              : Icons.play_circle,
                          size: 36,
                          color: AppColors.primary,
                        ),
                        onPressed: coord.toggle,
                      );
                    }),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: coord.playNext,
                    ),
                    IconButton(
                      tooltip: 'Stop and close player',
                      icon: const Icon(Icons.close),
                      // Full stop: tears down MediaSession + notification,
                      // resets paragraph highlight, hides mini player.
                      onPressed: coord.stop,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openChapter(BuildContext context, AudioState s) {
    final novel = s.novel;
    final chapter = s.chapter;
    if (novel == null || chapter == null) return;
    // No-op if we're already on the reader — avoids redundant push.
    if (GoRouterState.of(context).uri.path == '/reader') return;
    context.push('/reader',
        extra: ReaderArgs(novel: novel, chapter: chapter));
  }
}
