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
    final resp = await downloadService.startChapterDownload(req);
    await refresh();

    // Fire-and-forget poll
    () async {
      try {
        await downloadService.pollUntilComplete(
          resp.downloadId,
          onProgress: (status) {
            final next = {...state.active};
            next[resp.downloadId] = status;
            state = state.copyWith(active: next);
          },
        );
      } catch (_) {}
      final next = {...state.active}..remove(resp.downloadId);
      state = state.copyWith(active: next);
      await refresh();
    }();

    return resp.downloadId;
  }

  Future<void> deleteDownload(String downloadId) async {
    await downloadService.deleteDownload(downloadId);
    await refresh();
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, DownloadsState>(
  (_) => DownloadsNotifier(),
);
