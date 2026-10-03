import 'package:dio/dio.dart';

/// Attaches the access token to every backend request and reacts to the
/// backend rejecting it.
///
/// Constructed with its dependencies rather than reaching for globals so it
/// can be tested without secure storage or a live server.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.readToken, Future<void> Function()? onUnauthorized})
      : _onUnauthorized = onUnauthorized;

  /// Returns the current token, or null when signed out. Synchronous on
  /// purpose — this runs on every request, so it reads an in-memory value
  /// rather than hitting the keystore.
  final String? Function() readToken;

  Future<void> Function()? _onUnauthorized;

  /// Register what happens when the backend rejects our token. Set by the app
  /// widget, which owns the router needed to return to the login screen —
  /// the interceptor itself is attached earlier, before that exists.
  void setOnUnauthorized(Future<void> Function()? handler) {
    _onUnauthorized = handler;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  /// Endpoints whose 401 means "these credentials were rejected" (wrong
  /// password, unverifiable Google token) rather than "your session expired".
  /// The caller shows its own error; signing the user out would be wrong —
  /// for `/auth/google/link` the user is signed in and should stay so.
  static const _credentialPaths = ['/userLogin', '/auth/google', '/auth/google/link'];

  /// Set while [_onUnauthorized] runs, so a burst of 401s (several requests
  /// failing together) signs out and navigates once.
  Future<void>? _unauthorizedInFlight;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 401 means the token is missing, expired, or no longer trusted. The
    // backend deliberately uses 401 (not 403) for all of those so this single
    // branch catches them.
    if (err.response?.statusCode == 401 && _rejectsCurrentSession(err.requestOptions)) {
      final onUnauthorized = _onUnauthorized;
      if (onUnauthorized != null && _unauthorizedInFlight == null) {
        _unauthorizedInFlight =
            onUnauthorized().whenComplete(() => _unauthorizedInFlight = null);
      }
    }
    handler.next(err);
  }

  /// Whether a 401 on [request] invalidates the *current* session: it must
  /// not be a credential check, and it must have carried the token we hold
  /// now. A request sent with an older token (or none) that fails after the
  /// user signed in again says nothing about the new session.
  bool _rejectsCurrentSession(RequestOptions request) {
    // endsWith: `path` may be a full URL if a base URL with a prefix is used.
    final path = Uri.parse(request.path).path;
    if (_credentialPaths.any(path.endsWith)) return false;
    final token = readToken();
    if (token == null || token.isEmpty) return false;
    return request.headers['Authorization'] == 'Bearer $token';
  }
}
