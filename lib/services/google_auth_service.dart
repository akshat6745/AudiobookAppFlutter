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
  static const defaultServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

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
      final message = googleSignInFailureMessage(e);
      if (message == null) return null;
      throw GoogleAuthException(message);
    }

    // An account with no ID token is not a dismissed sheet. Android reports
    // that when this build's package and signing certificate are not
    // registered, and treating it as cancellation leaves the login screen
    // unchanged.
    return requireGoogleIdToken(account.authentication.idToken);
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

/// Message to show for a plugin failure, or null when the user dismissed
/// the account sheet.
///
/// Credential Manager reports some missing Android OAuth clients (package
/// name plus signing SHA-1) as [GoogleSignInExceptionCode.canceled] after the
/// user has already picked an account. Those descriptions are not a dismissal.
String? googleSignInFailureMessage(GoogleSignInException error) {
  final misconfigured =
      error.code == GoogleSignInExceptionCode.clientConfigurationError ||
      error.code == GoogleSignInExceptionCode.providerConfigurationError ||
      (error.code == GoogleSignInExceptionCode.canceled &&
          _cancelLooksLikeMisconfiguration(error));
  if (error.code == GoogleSignInExceptionCode.canceled && !misconfigured) {
    return null;
  }
  if (misconfigured) {
    return 'Google sign-in is misconfigured for this app build';
  }
  return "Couldn't sign in with Google";
}

bool _cancelLooksLikeMisconfiguration(GoogleSignInException error) {
  final text = '${error.description ?? ''} ${error.details ?? ''}'
      .toLowerCase();
  const markers = [
    'reauth',
    'developer',
    'sha',
    'misconfigured',
    '28444',
    '10:',
    'configuration',
  ];
  return markers.any(text.contains);
}

/// The ID token the backend verifies. Empty means Google accepted the account
/// but did not mint a token for this app build.
String requireGoogleIdToken(String? idToken) {
  if (idToken == null || idToken.isEmpty) {
    throw const GoogleAuthException(
      'Google sign-in is misconfigured for this app build',
    );
  }
  return idToken;
}
