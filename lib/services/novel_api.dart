import 'package:dio/dio.dart';

import '../models/novel.dart';
import 'api_client.dart';

/// Builds the multipart body for `POST /upload-epub`. Pure (no I/O beyond
/// reading the file into the multipart part) so the request shape can be
/// unit-tested without a network call.
FormData buildEpubUploadFormData({
  required String filePath,
  required String fileName,
}) {
  return FormData.fromMap({
    'file': MultipartFile.fromFileSync(filePath, filename: fileName),
  });
}

class NovelApi {
  // The library and upload endpoints identify the caller from the access
  // token, so neither takes a username any more.

  Future<List<Novel>> getAllNovels() async {
    final res = await apiClient.get('/novels');
    final data = res.data as List<dynamic>;
    return data
        .map((e) => Novel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  String coverUrl(String slug) =>
      '$apiBaseUrl/novel/${Uri.encodeComponent(slug)}/cover';

  /// Uploads an EPUB via the existing `POST /upload-epub` endpoint. Parsing
  /// + per-chapter upload on the backend can take well past the default
  /// timeout for a real book, so this call gets a generous 120s timeout
  /// (matching the sibling React Native client).
  Future<NovelUploadResponse> uploadEpub({
    required String filePath,
    required String fileName,
  }) async {
    final formData = buildEpubUploadFormData(
      filePath: filePath,
      fileName: fileName,
    );
    final res = await apiClient.post(
      '/upload-epub',
      data: formData,
      options: Options(
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    return NovelUploadResponse.fromJson(res.data as Map<String, dynamic>);
  }
}

final novelApi = NovelApi();
