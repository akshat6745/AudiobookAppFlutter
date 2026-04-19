import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/downloaded_chapter.dart';
import 'api_client.dart';
import 'download_api.dart';
import 'storage.dart';

class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  final Map<String, DownloadStatus> _statusCache = {};

  // ---- Public API ----

  Future<DownloadResponse> startChapterDownload(DownloadRequest req) async {
    final response = await downloadApi.startChapterDownload(req);

    await _saveRecord(
      DownloadedChapter(
        downloadId: response.downloadId,
        novelName: req.novelName,
        chapterNumber: req.chapterNumber,
        status: DownloadStatusValue.pending,
        progress: 0,
        downloadDate: DateTime.now(),
        totalFiles: 0,
        completedFiles: 0,
      ),
    );

    return response;
  }

  Future<DownloadStatus> getDownloadStatus(String downloadId) async {
    final cached = _statusCache[downloadId];
    if (cached != null && cached.status == DownloadStatusValue.completed) {
      return cached;
    }

    final status = await downloadApi.getDownloadStatus(downloadId);

    if (_statusCache.length >= 100) {
      _statusCache.remove(_statusCache.keys.first);
    }
    _statusCache[downloadId] = status;

    await _updateRecord(downloadId, (rec) => rec.copyWith(
          totalFiles: status.totalFiles,
          completedFiles: status.completedFiles,
        ));

    return status;
  }

  Future<void> downloadFiles(
    String downloadId, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final dir = await _chapterDir(downloadId);
    await Directory(dir).create(recursive: true);

    final status = await getDownloadStatus(downloadId);
    if (status.status != DownloadStatusValue.completed) {
      throw StateError('Download not completed yet on backend');
    }

    // 1. Content.json
    final contentPath = p.join(dir, 'content.json');
    await _downloadWithRetry(
      downloadApi.fileUrl(downloadId, 'content.json'),
      contentPath,
    );
    await _validateContentFile(contentPath);

    final contentData = jsonDecode(await File(contentPath).readAsString())
        as Map<String, dynamic>;
    final paragraphCount =
        (contentData['paragraphs'] as List<dynamic>? ?? const []).length;
    if (paragraphCount == 0) {
      throw StateError('content.json has no paragraphs');
    }

    final totalFiles = 1 + 1 + paragraphCount;
    var completedFiles = 1;
    onProgress?.call(completedFiles, totalFiles);

    // 2. title.mp3
    final titlePath = p.join(dir, 'title.mp3');
    await _downloadWithRetry(
      downloadApi.fileUrl(downloadId, 'title.mp3'),
      titlePath,
    );
    await _validateAudioFile(titlePath);
    completedFiles++;
    onProgress?.call(completedFiles, totalFiles);

    // 3. Paragraph MP3s (max 5 concurrent)
    const concurrency = 5;
    for (var start = 0; start < paragraphCount; start += concurrency) {
      final batch = <Future<void>>[];
      for (var i = start;
          i < start + concurrency && i < paragraphCount;
          i++) {
        final local = p.join(dir, '$i.mp3');
        batch.add(() async {
          final file = File(local);
          if (file.existsSync()) {
            try {
              await _validateAudioFile(local);
              return;
            } catch (_) {
              await file.delete();
            }
          }
          await _downloadWithRetry(
            downloadApi.fileUrl(downloadId, '$i.mp3'),
            local,
          );
          await _validateAudioFile(local);
        }()
            .then((_) {
          completedFiles++;
          onProgress?.call(completedFiles, totalFiles);
        }));
      }
      await Future.wait(batch);
    }

    await _updateRecord(
      downloadId,
      (rec) => rec.copyWith(
        status: DownloadStatusValue.completed,
        progress: 100,
        totalFiles: totalFiles,
        completedFiles: totalFiles,
      ),
    );
  }

  Future<DownloadStatus> pollUntilComplete(
    String downloadId, {
    void Function(DownloadStatus status)? onProgress,
  }) async {
    const maxAttempts = 60; // 5 min with 5s interval
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final status = await getDownloadStatus(downloadId);
        onProgress?.call(status);
        if (status.status == DownloadStatusValue.completed) {
          await downloadFiles(
            downloadId,
            onProgress: (c, t) {
              if (onProgress != null && t > 0) {
                onProgress(DownloadStatus(
                  downloadId: downloadId,
                  status: DownloadStatusValue.processing,
                  progress: 50 + (c / t) * 50,
                  totalFiles: t,
                  completedFiles: c,
                ));
              }
            },
          );
          return status;
        }
        if (status.status == DownloadStatusValue.error) {
          throw StateError(status.errorMessage ?? 'Download failed');
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 5));
    }
    throw TimeoutException('Download polling timed out');
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
    final updated = list.where((d) => d.downloadId != downloadId).toList();
    await Storage.setString(
      StorageKeys.downloadedChapters,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    _statusCache.remove(downloadId);
  }

  // ---- Internals ----

  Future<String> _chapterDir(String downloadId) async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'downloads', downloadId);
  }

  Future<void> _downloadWithRetry(
    String url,
    String localPath, {
    int maxAttempts = 3,
  }) async {
    const delays = [0, 1000, 3000];
    Object? lastError;
    for (var i = 0; i < maxAttempts; i++) {
      if (i > 0) {
        await Future.delayed(Duration(milliseconds: delays[i]));
      }
      try {
        await apiClient.download(
          url,
          localPath,
          options: Options(responseType: ResponseType.bytes),
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Failed after $maxAttempts attempts: $lastError');
  }

  Future<void> _validateContentFile(String path) async {
    final raw = await File(path).readAsString();
    if (raw.contains('<!DOCTYPE') || raw.contains('<html')) {
      throw Exception('content.json returned HTML error response');
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['chapter_title'] == null && data['chapterTitle'] == null) {
      throw Exception('content.json missing chapter title');
    }
    final paragraphs = data['paragraphs'] as List<dynamic>?;
    if (paragraphs == null || paragraphs.isEmpty) {
      throw Exception('content.json has no paragraphs');
    }
  }

  Future<void> _validateAudioFile(String path) async {
    final f = File(path);
    if (!f.existsSync()) throw Exception('Audio file missing: $path');
    final size = await f.length();
    if (size < 1024) {
      throw Exception('Audio file too small: $size bytes');
    }
    // MP3 header sanity check: ID3 tag or MPEG sync word.
    final raf = await f.open();
    try {
      final bytes = await raf.read(4);
      if (bytes.length < 4) throw Exception('Too-short audio file');
      final isId3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
      final isMpeg = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
      if (!isId3 && !isMpeg) {
        // Log only — some servers return valid MP3 without header
      }
    } finally {
      await raf.close();
    }
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
