import '../models/novel.dart';
import 'api_client.dart';

class NovelApi {
  Future<List<Novel>> getAllNovels({String? username}) async {
    final res = await apiClient.get(
      '/novels',
      queryParameters: username != null ? {'username': username} : null,
    );
    final data = res.data as List<dynamic>;
    return data
        .map((e) => Novel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  String coverUrl(String slug) =>
      '$apiBaseUrl/novel/${Uri.encodeComponent(slug)}/cover';
}

final novelApi = NovelApi();
