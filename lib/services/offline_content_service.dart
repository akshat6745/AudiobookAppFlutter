import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/chapter.dart';
import '../models/downloaded_chapter.dart';
import 'storage.dart';

/// Resolves downloaded chapter content / audio files from disk.
class OfflineContentService {
  static Future<String> get baseDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'downloads'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  static Future<String> chapterDir(String downloadId) async {
    return p.join(await baseDir, downloadId);
  }

  /// Find the completed download record for a given novel/chapter.
  Future<DownloadedChapter?> _findCompletedDownload(
    String novelName,
    int chapterNumber,
  ) async {
    final raw = await Storage.getString(StorageKeys.downloadedChapters);
    if (raw == null) return null;
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((e) => DownloadedChapter.fromJson(e as Map<String, dynamic>))
        .toList();
    try {
      return list.firstWhere(
        (d) =>
            d.novelName == novelName &&
            d.chapterNumber == chapterNumber &&
            d.status == DownloadStatusValue.completed,
      );
    } catch (_) {
      return null;
    }
  }

  /// Read offline chapter content (content.json). Returns null if not found.
  Future<ChapterContent?> getOfflineChapterContent(
    String novelName,
    int chapterNumber,
  ) async {
    final record = await _findCompletedDownload(novelName, chapterNumber);
    if (record == null) return null;

    final dir = await chapterDir(record.downloadId);
    final file = File(p.join(dir, 'content.json'));
    if (!file.existsSync()) return null;

    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final paragraphs = (data['paragraphs'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false);
      final title = (data['chapter_title'] ?? data['chapterTitle']) as String?;
      return ChapterContent(
        content: paragraphs,
        chapterNumber: chapterNumber,
        chapterTitle: title,
      );
    } catch (_) {
      return null;
    }
  }

  /// Offline audio paths for a chapter.
  /// Returns `{titleAudio, paragraphAudios}` where each entry in
  /// paragraphAudios may be null if the file is missing/invalid.
  Future<({String? titleAudio, List<String?> paragraphAudios})?>
      getOfflineChapterAudio(String novelName, int chapterNumber) async {
    final record = await _findCompletedDownload(novelName, chapterNumber);
    if (record == null) return null;

    final dir = await chapterDir(record.downloadId);
    final contentFile = File(p.join(dir, 'content.json'));
    if (!contentFile.existsSync()) return null;

    int paragraphCount;
    try {
      final data = jsonDecode(await contentFile.readAsString())
          as Map<String, dynamic>;
      paragraphCount = (data['paragraphs'] as List<dynamic>? ?? const []).length;
    } catch (_) {
      return null;
    }

    String? title;
    final titleFile = File(p.join(dir, 'title.mp3'));
    if (titleFile.existsSync() && (await titleFile.length()) > 1024) {
      title = titleFile.path;
    }

    final paragraphs = <String?>[];
    for (var i = 0; i < paragraphCount; i++) {
      final f = File(p.join(dir, '$i.mp3'));
      if (f.existsSync() && (await f.length()) > 1024) {
        paragraphs.add(f.path);
      } else {
        paragraphs.add(null);
      }
    }

    return (titleAudio: title, paragraphAudios: paragraphs);
  }
}

final offlineContentService = OfflineContentService();
