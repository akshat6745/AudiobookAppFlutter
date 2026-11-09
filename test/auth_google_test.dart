import 'package:audiobook_app/providers/auth_providers.dart';
import 'package:audiobook_app/services/google_auth_service.dart';
import 'package:audiobook_app/services/session_store.dart';
import 'package:audiobook_app/services/user_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

/// Stands in for the plugin-backed service, which needs platform channels.
class FakeGoogleAuthService extends GoogleAuthService {
  FakeGoogleAuthService({this.idToken, this.error})
    : super(serverClientId: 'test.apps.googleusercontent.com');

  /// Null models the user dismissing the Google sheet.
  final String? idToken;
  final GoogleAuthException? error;
  int signOutCalls = 0;

  @override
  Future<String?> signInAndGetIdToken() async {
    if (error != null) throw error!;
    return idToken;
  }

  @override
  Future<void> signOut() async => signOutCalls++;
}

class FakeUserApi extends UserApi {
  FakeUserApi({this.username, this.throwOnGoogle = false, this.googleError});

  /// Null models the backend rejecting the ID token.
  final String? username;
  final bool throwOnGoogle;
  final DioException? googleError;
  final List<String> receivedTokens = [];

  /// Rejects every password, standing in for a backend 401. Overridden so
  /// these tests never touch the network.
  @override
  Future<Session?> login(String username, String password) async => null;

  /// What a link attempt returns: the linked email, or a backend rejection.
  String? linkedEmail = 'me@gmail.com';
  DioException? linkError;
  bool deleteAccountResult = true;
  DioException? deleteError;
  int deleteCalls = 0;

  @override
  Future<bool> deleteAccount() async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
    return deleteAccountResult;
  }

  @override
  Future<String?> linkGoogle(String idToken) async {
    receivedTokens.add(idToken);
    if (linkError != null) throw linkError!;
    return linkedEmail;
  }

  @override
  Future<Session?> googleSignIn(String idToken) async {
    receivedTokens.add(idToken);
    if (googleError != null) throw googleError!;
    if (throwOnGoogle) throw Exception('network down');
    final name = username;
    if (name == null) return null;
    return Session(username: name, token: 'access-token-for-$name');
  }
}

/// In-memory stand-in for the keystore-backed store.
class FakeSessionStore extends SessionStore {
  Session? _session;

  @override
  Session? get current => _session;

  @override
  Future<Session?> load() async => _session;

  @override
  Future<void> save(Session session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

late FakeSessionStore sessions;

ProviderContainer _containerWith({
  required FakeUserApi api,
  required FakeGoogleAuthService google,
  String? initialUser,
}) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(
        (_) => AuthNotifier(
          initialUser: initialUser,
          api: api,
          google: google,
          sessions: sessions,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sessions = FakeSessionStore();
  });

  group('loginWithGoogle', () {
    test('signs in and stores the username the backend resolved', () async {
      final api = FakeUserApi(username: 'reader@gmail.com');
      final google = FakeGoogleAuthService(idToken: 'id-token-123');
      final container = _containerWith(api: api, google: google);

      final error = await container
          .read(authProvider.notifier)
          .loginWithGoogle();

      expect(error, isNull);
      expect(container.read(authProvider).user, 'reader@gmail.com');
      expect(container.read(authProvider).isLoading, isFalse);
      // The token is forwarded verbatim for server-side verification.
      expect(api.receivedTokens, ['id-token-123']);
    });

    test('persists the access token and username together', () async {
      final container = _containerWith(
        api: FakeUserApi(username: 'reader@gmail.com'),
        google: FakeGoogleAuthService(idToken: 'id-token-123'),
      );
      await container.read(authProvider.notifier).loginWithGoogle();

      // Both halves must be stored, or the next launch is a split brain:
      // a username that looks signed in with no token to authorise anything.
      expect(sessions.current?.username, 'reader@gmail.com');
      expect(sessions.current?.token, isNotEmpty);
    });

    test(
      'a backend response without an access token is not a sign-in',
      () async {
        // FakeUserApi returns null when there's no username to build a session
        // from — mirroring a response missing its access_token.
        final container = _containerWith(
          api: FakeUserApi(username: null),
          google: FakeGoogleAuthService(idToken: 'id-token-123'),
        );

        await container.read(authProvider.notifier).loginWithGoogle();

        expect(container.read(authProvider).user, isNull);
        expect(sessions.current, isNull);
      },
    );

    test(
      'cancelled sign-in reports no error and leaves user signed out',
      () async {
        final container = _containerWith(
          api: FakeUserApi(username: 'reader@gmail.com'),
          google: FakeGoogleAuthService(idToken: null),
        );

        final error = await container
            .read(authProvider.notifier)
            .loginWithGoogle();

        expect(error, isNull, reason: 'dismissing the sheet is not a failure');
        expect(container.read(authProvider).user, isNull);
        expect(container.read(authProvider).isLoading, isFalse);
      },
    );

    test('surfaces the message when Google sign-in fails', () async {
      final container = _containerWith(
        api: FakeUserApi(username: 'reader@gmail.com'),
        google: FakeGoogleAuthService(
          error: const GoogleAuthException('Google sign-in is misconfigured'),
        ),
      );

      final error = await container
          .read(authProvider.notifier)
          .loginWithGoogle();

      expect(error, 'Google sign-in is misconfigured');
      expect(container.read(authProvider).user, isNull);
    });

    test('reports an error when the backend rejects the token', () async {
      final container = _containerWith(
        api: FakeUserApi(username: null),
        google: FakeGoogleAuthService(idToken: 'id-token-123'),
      );

      final error = await container
          .read(authProvider.notifier)
          .loginWithGoogle();

      expect(error, isNotNull);
      expect(container.read(authProvider).user, isNull);
    });

    test(
      'a rejected Google token is not reported as a connection failure',
      () async {
        final container = _containerWith(
          api: FakeUserApi(
            googleError: DioException(
              requestOptions: RequestOptions(path: '/auth/google'),
              response: Response(
                requestOptions: RequestOptions(path: '/auth/google'),
                statusCode: 401,
                data: {'detail': 'Could not verify Google sign-in'},
              ),
            ),
          ),
          google: FakeGoogleAuthService(idToken: 'id-token-123'),
        );

        final error = await container
            .read(authProvider.notifier)
            .loginWithGoogle();

        expect(error, "Couldn't sign in with Google");
        expect(container.read(authProvider).user, isNull);
        expect(sessions.current, isNull);
      },
    );

    test(
      'a server the phone cannot reach is not a rejected Google token',
      () async {
        final container = _containerWith(
          api: FakeUserApi(
            googleError: DioException(
              requestOptions: RequestOptions(path: '/auth/google'),
              type: DioExceptionType.connectionError,
            ),
          ),
          google: FakeGoogleAuthService(idToken: 'id-token-123'),
        );

        final error = await container
            .read(authProvider.notifier)
            .loginWithGoogle();

        expect(error, "Couldn't reach the server. Check your connection.");
        expect(container.read(authProvider).user, isNull);
      },
    );

    test('reports an error when the request throws', () async {
      final container = _containerWith(
        api: FakeUserApi(throwOnGoogle: true),
        google: FakeGoogleAuthService(idToken: 'id-token-123'),
      );

      final error = await container
          .read(authProvider.notifier)
          .loginWithGoogle();

      expect(error, isNotNull);
      expect(container.read(authProvider).user, isNull);
      expect(container.read(authProvider).isLoading, isFalse);
    });
  });

  group('linkGoogle', () {
    Future<ProviderContainer> signedInAs(
      FakeUserApi api,
      FakeGoogleAuthService google,
    ) async {
      await sessions.save(const Session(username: 'Akshat', token: 'my-token'));
      return _containerWith(api: api, google: google, initialUser: 'Akshat');
    }

    test('links and reports the Google email', () async {
      final api = FakeUserApi();
      final container = await signedInAs(
        api,
        FakeGoogleAuthService(idToken: 'id-token-123'),
      );

      final result = await container.read(authProvider.notifier).linkGoogle();

      expect(result?.linked, isTrue);
      expect(result?.message, 'Linked me@gmail.com');
      expect(api.receivedTokens, ['id-token-123']);
    });

    test('keeps the user signed in as themselves', () async {
      // Linking adds a way in; it must not swap the session for a
      // Gmail-named one.
      final container = await signedInAs(
        FakeUserApi(),
        FakeGoogleAuthService(idToken: 'id-token-123'),
      );

      await container.read(authProvider.notifier).linkGoogle();

      expect(container.read(authProvider).user, 'Akshat');
      expect(sessions.current?.token, 'my-token');
    });

    test('a dismissed Google sheet returns null and changes nothing', () async {
      final api = FakeUserApi();
      final container = await signedInAs(
        api,
        FakeGoogleAuthService(idToken: null),
      );

      expect(await container.read(authProvider.notifier).linkGoogle(), isNull);
      expect(api.receivedTokens, isEmpty);
    });

    test("surfaces the backend's conflict message", () async {
      final api = FakeUserApi()
        ..linkError = DioException(
          requestOptions: RequestOptions(path: '/auth/google/link'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/google/link'),
            statusCode: 409,
            data: {
              'detail':
                  'That Google account is already linked to another account',
            },
          ),
        );
      final container = await signedInAs(
        api,
        FakeGoogleAuthService(idToken: 'id-token-123'),
      );

      final result = await container.read(authProvider.notifier).linkGoogle();

      expect(result?.linked, isFalse);
      expect(
        result?.message,
        'That Google account is already linked to another account',
      );
      expect(container.read(authProvider).user, 'Akshat');
    });

    test('surfaces a Google-side failure', () async {
      final container = await signedInAs(
        FakeUserApi(),
        FakeGoogleAuthService(
          error: const GoogleAuthException('Google sign-in is misconfigured'),
        ),
      );

      final result = await container.read(authProvider.notifier).linkGoogle();

      expect(result?.linked, isFalse);
      expect(result?.message, 'Google sign-in is misconfigured');
    });
  });

  group('logout', () {
    test('clears the token, the username and the Google session', () async {
      final google = FakeGoogleAuthService();
      await sessions.save(
        const Session(username: 'reader@gmail.com', token: 'some-token'),
      );
      final container = _containerWith(
        api: FakeUserApi(),
        google: google,
        initialUser: 'reader@gmail.com',
      );

      await container.read(authProvider.notifier).logout();

      expect(container.read(authProvider).user, isNull);
      expect(sessions.current, isNull, reason: 'token must not survive logout');
      // Without this the next sign-in silently reuses the same account.
      expect(google.signOutCalls, 1);
    });

    test('a rejected token signs the user out', () async {
      final google = FakeGoogleAuthService();
      await sessions.save(
        const Session(username: 'reader@gmail.com', token: 'expired-token'),
      );
      final container = _containerWith(
        api: FakeUserApi(),
        google: google,
        initialUser: 'reader@gmail.com',
      );

      // What the Dio interceptor calls on a 401 from the backend.
      await container.read(authProvider.notifier).onUnauthorized();

      expect(container.read(authProvider).user, isNull);
      expect(sessions.current, isNull);
    });
  });

  group('deleteAccount', () {
    test('deletes the account on the server and clears the local session',
        () async {
      final api = FakeUserApi();
      final google = FakeGoogleAuthService();
      await sessions.save(
        const Session(username: 'reader@gmail.com', token: 'some-token'),
      );
      final container = _containerWith(
        api: api,
        google: google,
        initialUser: 'reader@gmail.com',
      );

      final error = await container.read(authProvider.notifier).deleteAccount();

      expect(error, isNull);
      expect(api.deleteCalls, 1);
      expect(container.read(authProvider).user, isNull);
      expect(sessions.current, isNull);
      expect(google.signOutCalls, 1);
    });

    test('surfaces server error and keeps user signed in on failure', () async {
      final api = FakeUserApi()
        ..deleteError = DioException(
          requestOptions: RequestOptions(path: '/user/account'),
          response: Response(
            requestOptions: RequestOptions(path: '/user/account'),
            statusCode: 403,
            data: {
              'detail': 'This system account cannot be deleted via self-service.'
            },
          ),
        );
      await sessions.save(
        const Session(username: 'Akshat', token: 'some-token'),
      );
      final container = _containerWith(
        api: api,
        google: FakeGoogleAuthService(),
        initialUser: 'Akshat',
      );

      final error = await container.read(authProvider.notifier).deleteAccount();

      expect(
        error,
        'This system account cannot be deleted via self-service.',
      );
      expect(container.read(authProvider).user, 'Akshat');
      expect(sessions.current?.token, 'some-token');
    });
  });

  group('demo bypass removal', () {
    test('demo/demo is rejected like any other bad credentials', () async {
      // The old code special-cased demo/demo both up front and in the
      // network-failure catch block, so it signed in regardless of the API.
      final container = _containerWith(
        api: FakeUserApi(),
        google: FakeGoogleAuthService(),
      );

      final error = await container
          .read(authProvider.notifier)
          .login('demo', 'demo');

      expect(error, isNotNull);
      expect(container.read(authProvider).user, isNull);
      expect(sessions.current, isNull);
    });

    test('a rejected password creates no session', () async {
      final container = _containerWith(
        api: FakeUserApi(),
        google: FakeGoogleAuthService(),
      );

      expect(
        await container.read(authProvider.notifier).login('akshat', 'wrong'),
        isNotNull,
      );
      expect(sessions.current, isNull);
    });
  });
}
