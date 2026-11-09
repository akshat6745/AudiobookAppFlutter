import 'dart:io';

import 'package:audiobook_app/services/google_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  test('Android applicationId and release signing are configured for Play Store', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "com.speakingbooks.app"'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
  });

  group('googleSignInFailureMessage', () {
    test('a dismissed account sheet is not an error', () {
      expect(
        googleSignInFailureMessage(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.canceled,
            description: '[16] Cancelled by user.',
          ),
        ),
        isNull,
      );
    });

    test(
      'selecting an account that then fails reauth is a configuration error',
      () {
        // Credential Manager uses "canceled" for a missing Android OAuth client
        // after the user has already picked an account. Showing nothing there
        // looks like a successful tap that did not sign in.
        expect(
          googleSignInFailureMessage(
            const GoogleSignInException(
              code: GoogleSignInExceptionCode.canceled,
              description: '[16] Account reauth failed.',
            ),
          ),
          'Google sign-in is misconfigured for this app build',
        );
      },
    );

    test('an explicit client configuration error is shown', () {
      expect(
        googleSignInFailureMessage(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.clientConfigurationError,
            description: 'serverClientId must be provided on Android',
          ),
        ),
        'Google sign-in is misconfigured for this app build',
      );
    });
  });

  group('requireGoogleIdToken', () {
    test('keeps a token the backend can verify', () {
      expect(requireGoogleIdToken('id-token-123'), 'id-token-123');
    });

    test('an account with no ID token is a failed sign-in', () {
      expect(
        () => requireGoogleIdToken(null),
        throwsA(
          isA<GoogleAuthException>().having(
            (e) => e.message,
            'message',
            'Google sign-in is misconfigured for this app build',
          ),
        ),
      );
      expect(
        () => requireGoogleIdToken(''),
        throwsA(isA<GoogleAuthException>()),
      );
    });
  });
}
