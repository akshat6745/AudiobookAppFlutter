import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/google_auth_service.dart';
import '../services/session_store.dart';
import '../services/user_api.dart';

// Identity now rests on an access token, not on the username — every
// user-scoped endpoint derives the caller from the token. Both live together
// in SessionStore (keystore-backed); see that file for why they aren't split.

class AuthState {
  final String? user;
  final bool isLoading;
  const AuthState({this.user, this.isLoading = false});

  AuthState copyWith({String? user, bool? isLoading, bool clearUser = false}) =>
      AuthState(
        user: clearUser ? null : (user ?? this.user),
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  // initialUser is pre-read from SharedPreferences in main() so the router
  // sees the correct auth state synchronously on first render — no async
  // restore race that redirects to /login on every app start / web refresh.
  //
  // `api` and `google` are injectable so the sign-in flows can be tested
  // without platform channels or a live backend.
  AuthNotifier({
    String? initialUser,
    UserApi? api,
    GoogleAuthService? google,
    SessionStore? sessions,
  }) : _api = api ?? userApi,
       _google = google ?? googleAuthService,
       _sessions = sessions ?? sessionStore,
       super(AuthState(user: initialUser, isLoading: false));

  final UserApi _api;
  final GoogleAuthService _google;
  final SessionStore _sessions;

  /// Returns null on success, or a message safe to show. A rejected password
  /// and a server the phone cannot reach are different failures.
  Future<String?> login(String username, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      final session = await _api.login(username, password);
      if (session != null) {
        await _startSession(session);
        return null;
      }
      state = state.copyWith(isLoading: false);
      return 'Invalid username or password';
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false);
      final code = e.response?.statusCode;
      if (code == 400 || code == 401) return 'Invalid username or password';
      return "Couldn't reach the server. Check your connection.";
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return "Couldn't reach the server. Check your connection.";
    }
  }

  /// Signs in with Google: the plugin yields an ID token, the backend
  /// verifies it and returns the username this account maps to.
  ///
  /// Returns null when the user dismissed the Google sheet (nothing to
  /// report), or a message to display when sign-in genuinely failed.
  Future<String?> loginWithGoogle() async {
    state = state.copyWith(isLoading: true);
    try {
      final idToken = await _google.signInAndGetIdToken();
      if (idToken == null) {
        state = state.copyWith(isLoading: false);
        return null;
      }

      final session = await _api.googleSignIn(idToken);
      if (session == null) {
        state = state.copyWith(isLoading: false);
        return "Couldn't sign in with Google";
      }

      await _startSession(session);
      return null;
    } on GoogleAuthException catch (e) {
      state = state.copyWith(isLoading: false);
      return e.message;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false);
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return "Couldn't sign in with Google";
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] : null;
      if (code == 503 && detail is String && detail.isNotEmpty) return detail;
      return "Couldn't reach the server. Check your connection.";
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return "Couldn't reach the server. Check your connection.";
    }
  }

  /// Links a Google account to the signed-in account, so "Continue with
  /// Google" reaches this library afterwards. Doesn't touch [state]: the
  /// user stays signed in as themselves whatever happens.
  ///
  /// Returns null if the user dismissed the Google sheet, otherwise whether
  /// the link happened and a message to show.
  Future<({bool linked, String message})?> linkGoogle() async {
    try {
      final idToken = await _google.signInAndGetIdToken();
      if (idToken == null) return null;

      final email = await _api.linkGoogle(idToken);
      if (email == null) {
        return (linked: false, message: "Couldn't link your Google account");
      }
      return (
        linked: true,
        message: email.isEmpty ? 'Google account linked' : 'Linked $email',
      );
    } on GoogleAuthException catch (e) {
      return (linked: false, message: e.message);
    } on DioException catch (e) {
      // e.g. 409 "That Google account is already linked to another account"
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] : null;
      return (
        linked: false,
        message: detail is String && detail.isNotEmpty
            ? detail
            : "Couldn't reach the server. Check your connection.",
      );
    } catch (_) {
      return (linked: false, message: "Couldn't link your Google account");
    }
  }

  Future<void> _startSession(Session session) async {
    await _sessions.save(session);
    state = AuthState(user: session.username);
  }

  /// Drop the session without the user asking — used when the backend rejects
  /// our token (expired, or the secret was rotated).
  Future<void> onUnauthorized() => logout();

  Future<bool> register(String username, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      final ok = await _api.register(username, password);
      state = state.copyWith(isLoading: false);
      return ok;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  Future<void> logout() async {
    // Clear the Google session too, or the next sign-in silently reuses the
    // same account instead of letting the user pick one.
    await _google.signOut();
    await _sessions.clear();
    state = const AuthState();
  }

  /// Permanently deletes the signed-in account on the server and clears the
  /// local session. Returns null on success, or an error message to show.
  Future<String?> deleteAccount() async {
    state = state.copyWith(isLoading: true);
    try {
      final ok = await _api.deleteAccount();
      if (!ok) {
        state = state.copyWith(isLoading: false);
        return "Couldn't delete account";
      }
      await logout();
      return null;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false);
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] : null;
      if (detail is String && detail.isNotEmpty) return detail;
      return "Couldn't reach the server. Check your connection.";
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return "Couldn't delete account";
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
