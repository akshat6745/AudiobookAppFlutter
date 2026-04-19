import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/downloaded_chapter.dart';
import '../providers/download_providers.dart';
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
        child: Text('No downloaded chapters yet', style: TextStyle(color: AppColors.textMuted)),
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
                    _statusText(item, active),
                    style: const TextStyle(fontSize: 12),
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
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => ref
                    .read(downloadsProvider.notifier)
                    .deleteDownload(item.downloadId),
              ),
            ),
          );
        },
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

  String _statusText(DownloadedChapter item, DownloadStatus? active) {
    if (active != null) {
      return 'Downloading… ${active.progress.toStringAsFixed(0)}%';
    }
    switch (item.status) {
      case DownloadStatusValue.completed:
        return 'Ready for offline playback';
      case DownloadStatusValue.processing:
      case DownloadStatusValue.pending:
        return 'Preparing…';
      case DownloadStatusValue.error:
        return 'Failed';
    }
  }

  String _pretty(String slug) {
    return slug
        .split('-')
        .map((s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }
}
