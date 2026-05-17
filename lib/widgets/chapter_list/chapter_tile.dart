import 'package:flutter/material.dart';

import '../../models/chapter.dart';
import '../../models/downloaded_chapter.dart';
import '../../theme/app_theme.dart';

/// Single row in the chapter list. Renders the chapter number/title,
/// a "LAST READ" badge when applicable, plus download + play actions.
class ChapterTile extends StatelessWidget {
  const ChapterTile({
    super.key,
    required this.chapter,
    required this.isLastRead,
    required this.download,
    required this.onPlay,
    required this.onDownload,
  });

  final Chapter chapter;
  final bool isLastRead;
  final DownloadedChapter? download;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final downloaded = download?.status == DownloadStatusValue.completed;
    final downloading = download?.status == DownloadStatusValue.pending ||
        download?.status == DownloadStatusValue.processing;

    return Card(
      color: isLastRead
          ? AppColors.primary.withOpacity(0.12)
          : AppColors.cardDark,
      child: ListTile(
        title: Text(
          'Chapter ${chapter.chapterNumber}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chapter.chapterTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (isLastRead)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LAST READ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                downloaded
                    ? Icons.check_circle
                    : (downloading ? Icons.downloading : Icons.download),
                color: downloaded
                    ? AppColors.success
                    : (downloading ? AppColors.accent : Colors.white70),
              ),
              onPressed: downloaded || downloading ? null : onDownload,
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow, color: AppColors.primary),
              onPressed: onPlay,
            ),
          ],
        ),
        onTap: onPlay,
      ),
    );
  }
}
