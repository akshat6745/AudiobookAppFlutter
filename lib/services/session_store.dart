import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A signed-in session: the access token that authorises requests, plus the
/// username it belongs to (used only for display).
class Session {
  const Session({required this.username, required this.token});

  final String username;
  final String token;
}

/// Persists the session in the platform keystore.
///
/// The token and username are stored **together**, deliberately. They used to
/// be separate concerns — username in SharedPreferences, nothing else — but
/// splitting a credential from the name it belongs to creates a worse failure
/// than losing both: the router would see a username and believe the user is
/// signed in, while every request 401s because the token is gone. Stored as a
/// pair, a lost key is just a clean sign-out.
///
/// [current] is an in-memory cache so the request interceptor doesn't make a
/// platform channel call on every HTTP request. Call [load] once at startup.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _usernameKey = 'auth_username';

  final FlutterSecureStorage _storage;

  Session? _current;

  Session? get current => _current;

  /// Read the persisted session into memory. Returns it for convenience.
  Future<Session?> load() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final username = await _storage.read(key: _usernameKey);
      // Neither half is useful alone; treat a partial record as signed out.
      _current = (token != null && token.isNotEmpty && username != null)
          ? Session(username: username, token: token)
          : null;
    } catch (_) {
      // Keystore unavailable (or keys dropped after a restore) — the user
      // signs in again rather than the app failing to start.
      _current = null;
    }
    return _current;
  }

  Future<void> save(Session session) async {
    _current = session;
    try {
      await _storage.write(key: _tokenKey, value: session.token);
      await _storage.write(key: _usernameKey, value: session.username);
    } catch (_) {
      // In-memory session still works for this run.
    }
  }

  Future<void> clear() async {
    _current = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _usernameKey);
    } catch (_) {
      // Nothing more we can do; the in-memory session is already gone.
    }
  }
}

final sessionStore = SessionStore();
