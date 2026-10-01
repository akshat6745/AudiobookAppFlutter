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

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 401 means the token is missing, expired, or no longer trusted. The
    // backend deliberately uses 401 (not 403) for all of those so this single
    // branch catches them.
    if (err.response?.statusCode == 401) {
      _onUnauthorized?.call();
    }
    handler.next(err);
  }
}
