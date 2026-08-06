import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/downloaded_chapter.dart';
import '../services/download_service.dart';

class DownloadsState {
  final List<DownloadedChapter> items;
  final Map<String, DownloadStatus> active;
  final bool isLoading;

  const DownloadsState({
    this.items = const [],
    this.active = const {},
    this.isLoading = false,
  });

  DownloadsState copyWith({
    List<DownloadedChapter>? items,
    Map<String, DownloadStatus>? active,
    bool? isLoading,
  }) =>
      DownloadsState(
        items: items ?? this.items,
        active: active ?? this.active,
        isLoading: isLoading ?? this.isLoading,
      );
}

class DownloadsNotifier extends StateNotifier<DownloadsState> {
  DownloadsNotifier() : super(const DownloadsState(isLoading: true)) {
    refresh();
  }

  Future<void> refresh() async {
    final list = await downloadService.getDownloadedChapters();
    state = state.copyWith(items: list, isLoading: false);
  }

  bool isDownloaded(String novelName, int chapterNumber) {
    return state.items.any((d) =>
        d.novelName == novelName &&
        d.chapterNumber == chapterNumber &&
        d.status == DownloadStatusValue.completed);
  }

  Future<String> startDownload(DownloadRequest req) async {
    // Text-only download completes synchronously (no server audio pipeline);
    // audio is generated on-device at playback time. Errors surface via the
    // record's `error` status, so refresh either way.
    String downloadId = '';
    try {
      final resp = await downloadService.startChapterDownload(req);
      downloadId = resp.downloadId;
    } finally {
      await refresh();
    }
    return downloadId;
  }

  Future<void> deleteDownload(String downloadId) async {
    await downloadService.deleteDownload(downloadId);
    await refresh();
  }

  /// Re-fetch any missing or corrupt paragraph files for a chapter that's
  /// already marked complete. Returns the count still missing.
  Future<int> repairChapter(String downloadId) async {
    final missing = await downloadService.repairChapter(downloadId);
    await refresh();
    return missing;
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, DownloadsState>(
  (_) => DownloadsNotifier(),
);
