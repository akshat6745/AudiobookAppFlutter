import 'dart:io';

import 'package:audiobook_app/services/novel_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmpDir;
  late String epubPath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('novel_upload_test');
    epubPath = p.join(tmpDir.path, 'source-on-disk.epub');
    await File(epubPath).writeAsBytes([1, 2, 3, 4]);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('includes the file under the "file" field with the given filename', () {
    final formData = buildEpubUploadFormData(
      filePath: epubPath,
      fileName: 'My Book.epub',
    );

    expect(formData.files, hasLength(1));
    expect(formData.files.single.key, 'file');
    expect(formData.files.single.value.filename, 'My Book.epub');
  });

  test('sends no identity fields — the access token identifies the uploader', () {
    final formData = buildEpubUploadFormData(
      filePath: epubPath,
      fileName: 'My Book.epub',
    );

    // A username here used to decide which account owned the upload.
    expect(formData.fields, isEmpty);
  });
}
