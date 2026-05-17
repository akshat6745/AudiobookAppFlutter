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

  /// Per-novel progress lookup. Used when only one novel's progress needs
  /// to be refreshed (cheaper than the full list endpoint).
  Future<UserProgress?> getNovelProgress({
    required String username,
    required String novelSlug,
  }) async {
    try {
      final res = await apiClient.get(
        '/user/progress/${Uri.encodeComponent(novelSlug)}',
        queryParameters: {'username': username},
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        // Backend sometimes wraps the row, sometimes returns it bare.
        final inner = data['progress'];
        if (inner is Map<String, dynamic>) {
          return UserProgress.fromJson(inner);
        }
        if (data.containsKey('lastChapterRead')) {
          return UserProgress.fromJson(data);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

final userApi = UserApi();
