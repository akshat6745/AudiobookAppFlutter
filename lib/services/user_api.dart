import '../models/user_progress.dart';
import 'api_client.dart';

class UserApi {
  Future<bool> login(String username, String password) async {
    final res = await apiClient.post(
      '/userLogin',
      data: {'username': username, 'password': password},
    );
    final data = res.data as Map<String, dynamic>;
    return (data['status'] as String?)?.toLowerCase() == 'success';
  }

  Future<bool> register(String username, String password) async {
    final res = await apiClient.post(
      '/register',
      data: {'username': username, 'password': password},
    );
    final data = res.data as Map<String, dynamic>;
    return (data['status'] as String?)?.toLowerCase() == 'success';
  }

  Future<void> saveProgress({
    required String username,
    required String novelSlug,
    required int lastChapterRead,
  }) async {
    await apiClient.post(
      '/user/progress',
      data: {
        'username': username,
        'novelName': novelSlug,
        'lastChapterRead': lastChapterRead,
      },
    );
  }

  Future<List<UserProgress>> getUserProgress(String username) async {
    final res = await apiClient.get(
      '/user/progress',
      queryParameters: {'username': username},
    );
    final data = res.data as Map<String, dynamic>;
    final progress = data['progress'] as List<dynamic>? ?? const [];
    return progress
        .map((e) => UserProgress.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}

final userApi = UserApi();
