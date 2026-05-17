import 'package:flutter/material.dart';

import '../../models/chapter.dart';
import '../../models/downloaded_chapter.dart';
import '../../theme/app_theme.dart';
import 'chapter_tile.dart';

/// The middle section of the chapter list screen — handles loading,
/// error, and empty states for the current page and renders the list
/// of [ChapterTile]s otherwise. Pulled out of the screen to keep the
/// orchestrator small and to make the state-branching logic testable.
class ChapterListBody extends StatelessWidget {
  const ChapterListBody({
    super.key,
    required this.chapters,
    required this.isLoading,
    required this.error,
    required this.lastChapter,
    required this.downloads,
    required this.scrollController,
    required this.onRetry,
    required this.findDownload,
    required this.onPlay,
    required this.onDownload,
  });

  final List<Chapter> chapters;
  final bool isLoading;
  final Object? error;
  final int? lastChapter;
  final List<DownloadedChapter> downloads;
  final ScrollController scrollController;
  final VoidCallback onRetry;
  final DownloadedChapter? Function(Chapter) findDownload;
  final void Function(Chapter) onPlay;
  final Future<void> Function(Chapter) onDownload;

  @override
  Widget build(BuildContext context) {
    if (isLoading && chapters.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && chapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.accent, size: 32),
              const SizedBox(height: 12),
              Text(
                'Could not load chapters:\n$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (chapters.isEmpty) {
      return const Center(child: Text('No chapters on this page.'));
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: chapters.length,
      itemBuilder: (_, i) {
        final ch = chapters[i];
        return ChapterTile(
          chapter: ch,
          isLastRead: lastChapter == ch.chapterNumber,
          download: findDownload(ch),
          onPlay: () => onPlay(ch),
          onDownload: () => onDownload(ch),
        );
      },
    );
  }
}
