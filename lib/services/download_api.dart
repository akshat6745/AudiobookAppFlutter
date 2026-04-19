import '../models/downloaded_chapter.dart';
import 'api_client.dart';

class DownloadApi {
  Future<DownloadResponse> startChapterDownload(DownloadRequest req) async {
    final res = await apiClient.post('/download/chapter', data: req.toJson());
    return DownloadResponse.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DownloadStatus> getDownloadStatus(String downloadId) async {
    final res = await apiClient.get('/download/status/$downloadId');
    return DownloadStatus.fromJson(res.data as Map<String, dynamic>);
  }

  String fileUrl(String downloadId, String filename) =>
      '$apiBaseUrl/download/file/$downloadId/$filename';
}

final downloadApi = DownloadApi();
