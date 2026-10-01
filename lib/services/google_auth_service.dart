import 'package:google_sign_in/google_sign_in.dart';

/// Thrown when Google sign-in can't proceed. [message] is safe to show.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => 'GoogleAuthException: $message';
}

/// Wraps the `google_sign_in` plugin behind a two-method surface so
/// [AuthNotifier] can be tested with a fake instead of the real plugin
/// (which needs platform channels and a live Google account).
///
/// All this layer produces is an ID token; it is the backend that verifies it
/// and decides which account it maps to.
class GoogleAuthService {
  GoogleAuthService({String? serverClientId})
      : serverClientId = serverClientId ?? defaultServerClientId;

  /// The **Web** OAuth client ID — on Android the ID token is minted for that
  /// audience, and the backend verifies against the same value. Supplied at
  /// build time:
  ///
  /// ```
  /// flutter build apk --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com
  /// ```
  ///
  /// Not a secret (OAuth client IDs are public), just environment-specific.
  static const defaultServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String serverClientId;

  Future<void>? _initialization;

  bool get isConfigured => serverClientId.isNotEmpty;

  /// `initialize()` must finish before `authenticate()`; done lazily so app
  /// startup doesn't wait on a flow most launches never use.
  Future<void> _ensureInitialized() {
    return _initialization ??= GoogleSignIn.instance.initialize(
      serverClientId: serverClientId,
    );
  }

  /// Runs the interactive sign-in and returns the Google ID token.
  ///
  /// Returns null if the user dismissed the sheet. Throws
  /// [GoogleAuthException] with a user-presentable message otherwise.
  Future<String?> signInAndGetIdToken() async {
    if (!isConfigured) {
      throw const GoogleAuthException(
        'Google sign-in is not configured in this build',
      );
    }

    await _ensureInitialized();

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const GoogleAuthException(
        'Google sign-in is not supported on this device',
      );
    }

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      // A dismissed sheet is a normal outcome, not an error to report.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
        // Nearly always a missing/mismatched Android OAuth client: the
        // package name plus signing SHA-1 must be registered in Google Cloud.
        throw const GoogleAuthException(
          'Google sign-in is misconfigured for this app build',
        );
      }
      throw const GoogleAuthException("Couldn't sign in with Google");
    }

    return account.authentication.idToken;
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Local sign-out is best-effort; never block app logout on it.
    }
  }
}

final googleAuthService = GoogleAuthService();
