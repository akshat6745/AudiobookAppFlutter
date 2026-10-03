import 'dart:async';

import 'package:audiobook_app/services/auth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures what the interceptor forwards instead of hitting the network.
class _CapturingHandler extends RequestInterceptorHandler {
  RequestOptions? forwarded;

  @override
  void next(RequestOptions options) => forwarded = options;
}

class _CapturingErrorHandler extends ErrorInterceptorHandler {
  DioException? forwarded;

  @override
  void next(DioException err) => forwarded = err;
}

RequestOptions _request({String path = '/novels', String? sentToken}) =>
    RequestOptions(
      path: path,
      headers: {if (sentToken != null) 'Authorization': 'Bearer $sentToken'},
    );

/// A failed request that was sent with [sentToken] (the token the tests'
/// interceptors hold, by default).
DioException _errorWithStatus(
  int status, {
  String path = '/novels',
  String? sentToken = 'abc123',
}) {
  final request = _request(path: path, sentToken: sentToken);
  return DioException(
    requestOptions: request,
    response: Response(requestOptions: request, statusCode: status),
  );
}

void main() {
  group('attaching the token', () {
    test('sends the bearer header when signed in', () {
      final interceptor = AuthInterceptor(readToken: () => 'abc123');
      final handler = _CapturingHandler();

      interceptor.onRequest(_request(), handler);

      expect(handler.forwarded!.headers['Authorization'], 'Bearer abc123');
    });

    test('sends no header when signed out', () {
      final interceptor = AuthInterceptor(readToken: () => null);
      final handler = _CapturingHandler();

      interceptor.onRequest(_request(), handler);

      expect(handler.forwarded!.headers.containsKey('Authorization'), isFalse);
    });

    test('treats an empty token as signed out', () {
      final interceptor = AuthInterceptor(readToken: () => '');
      final handler = _CapturingHandler();

      interceptor.onRequest(_request(), handler);

      expect(handler.forwarded!.headers.containsKey('Authorization'), isFalse);
    });

    test('reads the token fresh on every request', () {
      // Signing in mid-session must not require rebuilding the Dio client.
      String? token;
      final interceptor = AuthInterceptor(readToken: () => token);

      final before = _CapturingHandler();
      interceptor.onRequest(_request(), before);
      expect(before.forwarded!.headers.containsKey('Authorization'), isFalse);

      token = 'fresh';
      final after = _CapturingHandler();
      interceptor.onRequest(_request(), after);
      expect(after.forwarded!.headers['Authorization'], 'Bearer fresh');
    });
  });

  group('reacting to a rejected token', () {
    test('runs the handler on 401', () {
      var calls = 0;
      final interceptor = AuthInterceptor(
        readToken: () => 'abc123',
        onUnauthorized: () async => calls++,
      );

      interceptor.onError(_errorWithStatus(401), _CapturingErrorHandler());

      expect(calls, 1);
    });

    test('ignores other failures', () {
      var calls = 0;
      final interceptor = AuthInterceptor(
        readToken: () => 'abc123',
        onUnauthorized: () async => calls++,
      );

      for (final status in [400, 403, 404, 500, 503]) {
        interceptor.onError(_errorWithStatus(status), _CapturingErrorHandler());
      }

      // A 500 or a 404 must not sign the user out.
      expect(calls, 0);
    });

    test('still forwards the error so callers can handle it', () {
      final interceptor = AuthInterceptor(
        readToken: () => 'abc123',
        onUnauthorized: () async {},
      );
      final handler = _CapturingErrorHandler();

      interceptor.onError(_errorWithStatus(401), handler);

      expect(handler.forwarded, isNotNull);
    });

    test('survives a 401 with no handler registered', () {
      final interceptor = AuthInterceptor(readToken: () => 'abc123');
      final handler = _CapturingErrorHandler();

      interceptor.onError(_errorWithStatus(401), handler);

      expect(handler.forwarded, isNotNull);
    });

    test('setOnUnauthorized registers the handler after construction', () {
      // The app attaches the interceptor before the router exists.
      var calls = 0;
      final interceptor = AuthInterceptor(readToken: () => 'abc123');
      interceptor.setOnUnauthorized(() async => calls++);

      interceptor.onError(_errorWithStatus(401), _CapturingErrorHandler());

      expect(calls, 1);
    });

    test('a rejected credential check does not sign the user out', () {
      // e.g. /auth/google/link rejecting the Google token while signed in.
      var calls = 0;
      final interceptor = AuthInterceptor(
        readToken: () => 'abc123',
        onUnauthorized: () async => calls++,
      );

      for (final path in ['/userLogin', '/auth/google', '/auth/google/link']) {
        final handler = _CapturingErrorHandler();
        interceptor.onError(_errorWithStatus(401, path: path), handler);
        expect(handler.forwarded, isNotNull, reason: path);
      }
      interceptor.onError(
        _errorWithStatus(401, path: 'https://api.example.com/v1/auth/google/link'),
        _CapturingErrorHandler(),
      );

      expect(calls, 0);
    });

    test('a late 401 for an older token does not sign out the new session', () {
      var calls = 0;
      final interceptor = AuthInterceptor(
        readToken: () => 'fresh',
        onUnauthorized: () async => calls++,
      );

      interceptor.onError(
        _errorWithStatus(401, sentToken: 'expired'),
        _CapturingErrorHandler(),
      );
      interceptor.onError(
        _errorWithStatus(401, sentToken: null),
        _CapturingErrorHandler(),
      );

      expect(calls, 0);
    });

    test('ignores a 401 when already signed out', () {
      var calls = 0;
      final interceptor = AuthInterceptor(
        readToken: () => null,
        onUnauthorized: () async => calls++,
      );

      interceptor.onError(_errorWithStatus(401), _CapturingErrorHandler());

      expect(calls, 0);
    });

    test('a burst of 401s runs the handler once', () async {
      var calls = 0;
      final release = Completer<void>();
      final interceptor = AuthInterceptor(
        readToken: () => 'abc123',
        onUnauthorized: () async {
          calls++;
          await release.future; // sign-out still in progress
        },
      );

      for (var i = 0; i < 3; i++) {
        interceptor.onError(_errorWithStatus(401), _CapturingErrorHandler());
      }
      expect(calls, 1);

      // Once it finishes, a genuinely new rejection is handled again.
      release.complete();
      await Future<void>.delayed(Duration.zero);
      interceptor.onError(_errorWithStatus(401), _CapturingErrorHandler());
      expect(calls, 2);
    });
  });
}
