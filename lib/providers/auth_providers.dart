import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage.dart';
import '../services/user_api.dart';

// Username is not sensitive on its own (no token / password is stored;
// the API just echoes the username back as a query parameter). Plain
// SharedPreferences is far more reliable than the Android Keystore-backed
// FlutterSecureStorage, which has been observed to lose keys after device
// restarts or aggressive battery management.
const _userKey = 'auth_user';

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
  AuthNotifier({String? initialUser})
      : super(AuthState(user: initialUser, isLoading: false));

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      // Demo bypass
      if (username == 'demo' && password == 'demo') {
        await Storage.setString(_userKey, username);
        state = AuthState(user: username);
        return true;
      }
      final ok = await userApi.login(username, password);
      if (ok) {
        await Storage.setString(_userKey, username);
        state = AuthState(user: username);
        return true;
      }
      state = state.copyWith(isLoading: false);
      return false;
    } catch (_) {
      // Fallback to demo if network error
      if (username == 'demo' && password == 'demo') {
        await Storage.setString(_userKey, username);
        state = AuthState(user: username);
        return true;
      }
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  Future<bool> register(String username, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      final ok = await userApi.register(username, password);
      state = state.copyWith(isLoading: false);
      return ok;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  Future<void> logout() async {
    await Storage.remove(_userKey);
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
