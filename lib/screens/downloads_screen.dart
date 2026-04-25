import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/chapter.dart';
import '../models/downloaded_chapter.dart';
import '../models/novel.dart';
import '../providers/download_providers.dart';
import '../router.dart';
import '../services/offline_content_service.dart';
import '../theme/app_theme.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadsProvider);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty) {
      return const Center(
        child: Text('No downloaded chapters yet',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(downloadsProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: state.items.length,
        itemBuilder: (_, i) {
          final item = state.items[i];
          final active = state.active[item.downloadId];
          final ready = active == null &&
              item.status == DownloadStatusValue.completed;
          // A "complete" record can still have gaps if some paragraphs
          // failed every retry. Surface a repair button for those.
          final hasGaps = ready &&
              item.totalFiles > 0 &&
              item.completedFiles < item.totalFiles;
          return Card(
            child: ListTile(
              leading: _statusIcon(item, active),
              title: Text(
                '${_pretty(item.novelName)} — Ch ${item.chapterNumber}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusText(item, active, hasGaps: hasGaps),
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          hasGaps ? AppColors.accent : null,
                    ),
                  ),
                  if (active != null &&
                      active.status == DownloadStatusValue.processing)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(
                        value: active.progress / 100,
                        minHeight: 3,
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasGaps)
                    IconButton(
                      tooltip: 'Retry missing paragraphs',
                      icon: const Icon(Icons.refresh,
                          color: AppColors.accent),
                      onPressed: () =>
                          _repairChapter(context, ref, item.downloadId),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ref
                        .read(downloadsProvider.notifier)
                        .deleteDownload(item.downloadId),
                  ),
                ],
              ),
              onTap: ready ? () => _openReader(context, item) : null,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openReader(
      BuildContext context, DownloadedChapter item) async {
    // Read the chapter title from the downloaded content.json so the
    // reader's metadata renders the real chapter name instead of an
    // empty string. Fall back to a generic title if anything fails.
    String chapterTitle = 'Chapter ${item.chapterNumber}';
    try {
      final offline = await offlineContentService.getOfflineChapterContent(
        item.novelName,
        item.chapterNumber,
      );
      if (offline?.chapterTitle != null && offline!.chapterTitle!.isNotEmpty) {
        chapterTitle = offline.chapterTitle!;
      }
    } catch (_) {}

    if (!context.mounted) return;
    context.push(
      '/reader',
      extra: ReaderArgs(
        novel: Novel(
          id: item.novelName,
          slug: item.novelName,
          title: _pretty(item.novelName),
          author: null,
          chapterCount: null,
          source: NovelSource.cloudflareD1,
          description: null,
          isPublic: false,
        ),
        chapter: Chapter(
          chapterNumber: item.chapterNumber,
          chapterTitle: chapterTitle,
        ),
      ),
    );
  }

  Widget _statusIcon(DownloadedChapter item, DownloadStatus? active) {
    if (active != null || item.status == DownloadStatusValue.processing) {
      return const Icon(Icons.downloading, color: AppColors.accent);
    }
    switch (item.status) {
      case DownloadStatusValue.completed:
        return const Icon(Icons.check_circle, color: AppColors.success);
      case DownloadStatusValue.error:
        return const Icon(Icons.error, color: AppColors.error);
      default:
        return const Icon(Icons.download, color: AppColors.primary);
    }
  }

  String _statusText(
    DownloadedChapter item,
    DownloadStatus? active, {
    bool hasGaps = false,
  }) {
    if (active != null) {
      return 'Downloading… ${active.progress.toStringAsFixed(0)}%';
    }
    switch (item.status) {
      case DownloadStatusValue.completed:
        if (hasGaps) {
          return '${item.completedFiles}/${item.totalFiles} paragraphs · '
              'tap retry to fetch missing';
        }
        return 'Tap to play offline';
      case DownloadStatusValue.processing:
      case DownloadStatusValue.pending:
        return 'Preparing…';
      case DownloadStatusValue.error:
        return 'Failed';
    }
  }

  Future<void> _repairChapter(
    BuildContext context,
    WidgetRef ref,
    String downloadId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Retrying missing paragraphs…')),
    );
    final stillMissing =
        await ref.read(downloadsProvider.notifier).repairChapter(downloadId);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          stillMissing == 0
              ? 'All paragraphs downloaded'
              : '$stillMissing paragraph(s) still unavailable',
        ),
      ),
    );
  }

  String _pretty(String slug) {
    return slug
        .split('-')
        .map((s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }
}
