import 'package:dio/dio.dart';

import 'api_client.dart';

/// Pre-rendered StyleTTS audio in R2, under
/// `audio-student/styletts2-eye-v1/<slug>/chapter_<n>/`.
///
/// A chapter is ready only when its manifest lists `title.opus`,
/// `chapter.opus`, and a contiguous `0.opus`..(N-1).opus that covers every
/// playable paragraph. Playback index 0 is the spoken title; body paragraph
/// k in the reader (after the synthetic title line) is stored as `(k-1).opus`.
const studentAudioPrefix = 'audio-student/styletts2-eye-v1';

final _slugPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final _imageParagraph = RegExp(r'^\[IMAGE:.*\]$', caseSensitive: false);
final _numberedOpus = RegExp(r'^(\d+)\.opus$');

class SavedAudioTarget {
  const SavedAudioTarget({
    required this.slug,
    required this.chapterNumber,
    required this.lines,
  });

  final String slug;
  final int chapterNumber;

  /// Chapter lines from the API, without the reader's synthetic title.
  final List<String> lines;

  @override
  bool operator ==(Object other) =>
      other is SavedAudioTarget &&
      other.slug == slug &&
      other.chapterNumber == chapterNumber &&
      _sameLines(other.lines, lines);

  @override
  int get hashCode => Object.hash(slug, chapterNumber, lines.length);
}

bool _sameLines(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool isImageParagraph(String? text) {
  if (text == null) return false;
  return _imageParagraph.hasMatch(text.trim());
}

/// Source indexes of lines that can be spoken. Image placeholders and blank
/// lines keep their index but are not playable.
List<int>? playableSourceIndexes(List<String> lines) {
  final indexes = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final text = lines[i].trim();
    if (text.isEmpty || isImageParagraph(text)) continue;
    indexes.add(i);
  }
  if (indexes.isEmpty) return null;
  if (indexes.toSet().length != indexes.length) return null;
  return indexes;
}

Set<int> skippedSourceIndexes(List<String> lines) {
  final skipped = <int>{};
  for (var i = 0; i < lines.length; i++) {
    final text = lines[i].trim();
    if (text.isEmpty || isImageParagraph(text)) skipped.add(i);
  }
  return skipped;
}

/// Opus filenames named anywhere in a chapter manifest.
List<String>? manifestOpusFiles(Object? manifest) {
  if (manifest is! Map) return null;
  final names = <String>{};
  void visit(Object? value, int depth) {
    if (depth > 6 || value == null) return;
    if (value is String && _isOpusName(value)) {
      names.add(value);
      return;
    }
    if (value is List) {
      for (final item in value) {
        visit(item, depth + 1);
      }
      return;
    }
    if (value is Map) {
      final file = value['file'];
      if (file is String && _isOpusName(file)) names.add(file);
      visit(value['title'], depth + 1);
      visit(value['paragraphs'], depth + 1);
      visit(value['chapter_file'], depth + 1);
      final files = value['files'];
      if (files is List) {
        for (final item in files) {
          visit(item, depth + 1);
        }
      } else if (files is Map) {
        for (final key in files.keys) {
          if (key is String && _isOpusName(key)) names.add(key);
        }
      }
    }
  }

  visit(manifest, 0);
  return names.toList();
}

bool _isOpusName(String value) =>
    value == 'title.opus' ||
    value == 'chapter.opus' ||
    _numberedOpus.hasMatch(value);

Set<int> manifestSilentIndexes(Object? manifest) {
  final silent = <int>{};
  if (manifest is! Map) return silent;
  final paragraphs = manifest['paragraphs'];
  if (paragraphs is! List) return silent;
  for (final item in paragraphs) {
    if (item is! Map || item['silent'] != true) continue;
    final index = item['index'];
    if (index is int && index >= 0) {
      silent.add(index);
      continue;
    }
    final file = item['file'];
    if (file is String) {
      final match = _numberedOpus.firstMatch(file);
      if (match != null) silent.add(int.parse(match.group(1)!));
    }
  }
  return silent;
}

/// True when [lines] are fully covered by a stored chapter manifest.
bool studentChapterIsComplete(Object? manifest, List<String> lines) {
  final files = manifestOpusFiles(manifest);
  if (files == null) return false;
  final fileSet = files.toSet();
  if (!fileSet.contains('title.opus') || !fileSet.contains('chapter.opus')) {
    return false;
  }

  final indexes = playableSourceIndexes(lines);
  if (indexes == null) return false;

  final numbered = files
      .map((name) => _numberedOpus.firstMatch(name))
      .whereType<RegExpMatch>()
      .map((match) => int.parse(match.group(1)!))
      .toList()
    ..sort();
  if (numbered.isEmpty) return false;
  for (var i = 0; i < numbered.length; i++) {
    if (numbered[i] != i) return false;
  }
  if (indexes.any((index) => index < 0 || index >= numbered.length)) {
    return false;
  }

  final playable = indexes.toSet();
  final silent = manifestSilentIndexes(manifest);
  final skipped = skippedSourceIndexes(lines);
  for (var i = 0; i < numbered.length; i++) {
    if (!playable.contains(i) && !silent.contains(i) && !skipped.contains(i)) {
      return false;
    }
  }
  return true;
}

/// `title` for the spoken chapter title, otherwise the stored paragraph index.
String savedParagraphParam(int playbackIndex) {
  if (playbackIndex <= 0) return 'title';
  return '${playbackIndex - 1}';
}

class SavedChapterAudio {
  SavedChapterAudio({Dio? client}) : _client = client ?? apiClient;

  final Dio _client;

  Future<bool> isChapterComplete(SavedAudioTarget target) async {
    final slug = target.slug.trim().toLowerCase();
    if (!_slugPattern.hasMatch(slug) || target.chapterNumber < 1) return false;
    if (playableSourceIndexes(target.lines) == null) return false;
    final manifest = await _fetchManifest(slug, target.chapterNumber);
    if (manifest == null) return false;
    return studentChapterIsComplete(manifest, target.lines);
  }

  /// Downloads one stored Opus file. [playbackIndex] 0 is the title.
  Future<List<int>?> downloadParagraph({
    required String novel,
    required int chapter,
    required int playbackIndex,
  }) async {
    final slug = novel.trim().toLowerCase();
    if (!_slugPattern.hasMatch(slug) || chapter < 1 || playbackIndex < 0) {
      return null;
    }
    try {
      final response = await _client.get<List<int>>(
        '/student-audio/paragraph',
        queryParameters: {
          'novel': slug,
          'chapter': '$chapter',
          'paragraph': savedParagraphParam(playbackIndex),
        },
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
          headers: const {'Accept': 'audio/ogg'},
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.length < 4) return null;
      if (String.fromCharCodes(bytes.take(4)) != 'OggS') return null;
      return bytes;
    } on DioException {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchManifest(String slug, int chapter) async {
    try {
      final response = await _client.get<dynamic>(
        '/student-audio/$studentAudioPrefix/$slug/chapter_$chapter/manifest.json',
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } on DioException {
      return null;
    }
  }
}
