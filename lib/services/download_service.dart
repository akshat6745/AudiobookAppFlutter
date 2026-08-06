import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/downloaded_chapter.dart';
import 'chapter_api.dart';
import 'storage.dart';

/// Offline downloads store the chapter's **text only**. Audio is synthesized
/// on-device by the TTS engine at playback time (see [AudioCacheManager]), so a
/// "download" just persists the chapter's paragraphs to `content.json`. This
/// keeps downloads instant and fully offline — no server-side audio, no MP3s.
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  /// Fetch a chapter's text and store it for offline reading + on-device audio.
  /// Idempotent per (novel, chapter). The returned response is already
  /// completed — there is nothing further to poll.
  Future<DownloadResponse> startChapterDownload(DownloadRequest req) async {
    final downloadId = _localId(req.novelName, req.chapterNumber);

    await _saveRecord(
      DownloadedChapter(
        downloadId: downloadId,
        novelName: req.novelName,
        chapterNumber: req.chapterNumber,
        status: DownloadStatusValue.processing,
        progress: 0,
        downloadDate: DateTime.now(),
        totalFiles: 1,
        completedFiles: 0,
      ),
    );

    try {
      await _fetchAndStoreContent(downloadId, req.novelName, req.chapterNumber);
    } catch (e) {
      await _updateRecord(
        downloadId,
        (r) => r.copyWith(status: DownloadStatusValue.error),
      );
      rethrow;
    }

    return DownloadResponse(
      downloadId: downloadId,
      status: 'completed',
      message: 'Chapter text saved for offline playback',
    );
  }

  /// Re-fetch the chapter text if the local copy is missing or unreadable.
  /// Returns 0 on success, -1 if the record/content can't be recovered.
  Future<int> repairChapter(String downloadId) async {
    final record = await _findRecord(downloadId);
    if (record == null) return -1;
    try {
      await _fetchAndStoreContent(
        downloadId,
        record.novelName,
        record.chapterNumber,
      );
      return 0;
    } catch (_) {
      return -1;
    }
  }

  Future<List<DownloadedChapter>> getDownloadedChapters() async {
    final raw = await Storage.getString(StorageKeys.downloadedChapters);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => DownloadedChapter.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<bool> isChapterDownloaded(String novelName, int chapterNumber) async {
    final list = await getDownloadedChapters();
    return list.any((d) =>
        d.novelName == novelName &&
        d.chapterNumber == chapterNumber &&
        d.status == DownloadStatusValue.completed);
  }

  Future<void> deleteDownload(String downloadId) async {
    final dir = await _chapterDir(downloadId);
    final d = Directory(dir);
    if (d.existsSync()) {
      await d.delete(recursive: true);
    }
    final list = await getDownloadedChapters();
    final updated = list.where((e) => e.downloadId != downloadId).toList();
    await Storage.setString(
      StorageKeys.downloadedChapters,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  // ---- Internals ----

  /// Fetch chapter content over the network and write `content.json` in the
  /// shape [OfflineContentService] reads (`chapter_title` + `paragraphs`), then
  /// mark the record complete.
  Future<void> _fetchAndStoreContent(
    String downloadId,
    String novelName,
    int chapterNumber,
  ) async {
    final content = await chapterApi.getChapterContent(
      chapterNumber: chapterNumber,
      novelSlug: novelName,
    );
    if (content.content.isEmpty) {
      throw StateError('Chapter has no content');
    }

    final dir = await _chapterDir(downloadId);
    await Directory(dir).create(recursive: true);
    await File(p.join(dir, 'content.json')).writeAsString(
      jsonEncode({
        'chapter_title': content.chapterTitle ?? '',
        'paragraphs': content.content,
      }),
    );

    await _updateRecord(
      downloadId,
      (r) => r.copyWith(
        status: DownloadStatusValue.completed,
        chapterTitle: content.chapterTitle,
        progress: 100,
        totalFiles: 1,
        completedFiles: 1,
      ),
    );
  }

  /// Deterministic local id per (novel, chapter) so re-downloading is idempotent.
  String _localId(String novel, int chapter) =>
      'local_${novel}_$chapter'.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

  Future<String> _chapterDir(String downloadId) async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'downloads', downloadId);
  }

  Future<DownloadedChapter?> _findRecord(String downloadId) async {
    final list = await getDownloadedChapters();
    for (final r in list) {
      if (r.downloadId == downloadId) return r;
    }
    return null;
  }

  Future<void> _saveRecord(DownloadedChapter record) async {
    final list = await getDownloadedChapters();
    final idx = list.indexWhere((e) => e.downloadId == record.downloadId);
    final updated = [...list];
    if (idx >= 0) {
      updated[idx] = record;
    } else {
      updated.add(record);
    }
    await Storage.setString(
      StorageKeys.downloadedChapters,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _updateRecord(
    String downloadId,
    DownloadedChapter Function(DownloadedChapter rec) patch,
  ) async {
    final list = await getDownloadedChapters();
    final idx = list.indexWhere((e) => e.downloadId == downloadId);
    if (idx < 0) return;
    final updated = [...list];
    updated[idx] = patch(list[idx]);
    await Storage.setString(
      StorageKeys.downloadedChapters,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }
}

final downloadService = DownloadService.instance;
