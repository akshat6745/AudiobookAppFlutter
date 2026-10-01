import '../models/user_progress.dart';
import 'api_client.dart';
import 'session_store.dart';

class UserApi {
  /// Signs in and returns the resulting session, or null if the credentials
  /// were rejected.
  Future<Session?> login(String username, String password) async {
    final res = await apiClient.post(
      '/userLogin',
      data: {'username': username, 'password': password},
    );
    return _sessionFrom(res.data, fallbackUsername: username);
  }

  Future<bool> register(String username, String password) async {
    final res = await apiClient.post(
      '/register',
      data: {'username': username, 'password': password},
    );
    final data = res.data as Map<String, dynamic>;
    return (data['status'] as String?)?.toLowerCase() == 'success';
  }

  /// Exchanges a Google ID token for a session.
  ///
  /// The backend verifies the ID token and resolves (or creates) the account,
  /// returning the access token the rest of the app authenticates with.
  /// Returns null if the backend rejected the ID token.
  Future<Session?> googleSignIn(String idToken) async {
    final res = await apiClient.post(
      '/auth/google',
      data: {'idToken': idToken},
    );
    return _sessionFrom(res.data);
  }

  /// Links a Google identity to the signed-in account (the access token is
  /// attached by the interceptor). Returns the linked Google email, or null
  /// if the backend didn't confirm the link. Conflicts arrive as a
  /// DioException carrying the backend's `detail`.
  Future<String?> linkGoogle(String idToken) async {
    final res = await apiClient.post(
      '/auth/google/link',
      data: {'idToken': idToken},
    );
    final data = res.data;
    if (data is! Map<String, dynamic> || data['linked'] != true) return null;
    return (data['email'] as String?) ?? '';
  }

  /// Parses a sign-in response. A session needs both an access token and a
  /// username; anything less counts as a failed sign-in.
  Session? _sessionFrom(dynamic body, {String? fallbackUsername}) {
    if (body is! Map<String, dynamic>) return null;
    if ((body['status'] as String?)?.toLowerCase() != 'success') return null;

    final token = body['access_token'] as String?;
    if (token == null || token.isEmpty) return null;

    final username = (body['username'] as String?) ?? fallbackUsername;
    if (username == null || username.isEmpty) return null;

    return Session(username: username, token: token);
  }

  // The progress endpoints identify the caller from the access token the
  // interceptor attaches, so none of them take a username any more.

  Future<void> saveProgress({
    required String novelSlug,
    required int lastChapterRead,
  }) async {
    await apiClient.post(
      '/user/progress',
      data: {
        'novelName': novelSlug,
        'lastChapterRead': lastChapterRead,
      },
    );
  }

  Future<List<UserProgress>> getUserProgress() async {
    final res = await apiClient.get('/user/progress');
    final data = res.data as Map<String, dynamic>;
    final progress = data['progress'] as List<dynamic>? ?? const [];
    return progress
        .map((e) => UserProgress.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Per-novel progress lookup. Used when only one novel's progress needs
  /// to be refreshed (cheaper than the full list endpoint).
  Future<UserProgress?> getNovelProgress({
    required String novelSlug,
  }) async {
    try {
      final res = await apiClient.get(
        '/user/progress/${Uri.encodeComponent(novelSlug)}',
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
