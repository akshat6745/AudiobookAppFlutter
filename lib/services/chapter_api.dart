import '../models/chapter.dart';
import 'api_client.dart';

class ChapterApi {
  Future<ChapterListResponse> getChaptersList(
    String novelSlug, {
    int page = 1,
  }) async {
    final res = await apiClient.get(
      '/chapters-with-pages/${Uri.encodeComponent(novelSlug)}',
      queryParameters: {'page': page},
    );
    return ChapterListResponse.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ChapterContent> getChapterContent({
    required int chapterNumber,
    required String novelSlug,
  }) async {
    final res = await apiClient.get(
      '/chapter',
      queryParameters: {
        'chapterNumber': chapterNumber,
        'novelName': novelSlug,
      },
    );
    return ChapterContent.fromJson(res.data as Map<String, dynamic>);
  }
}

final chapterApi = ChapterApi();
