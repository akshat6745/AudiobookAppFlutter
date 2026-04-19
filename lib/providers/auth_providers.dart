import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/user_api.dart';

const _secureStorage = FlutterSecureStorage();
const _userKey = 'user';

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
  AuthNotifier() : super(const AuthState(isLoading: true)) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final stored = await _secureStorage.read(key: _userKey);
      state = AuthState(user: stored, isLoading: false);
    } catch (_) {
      state = const AuthState(isLoading: false);
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      // Demo bypass
      if (username == 'demo' && password == 'demo') {
        await _secureStorage.write(key: _userKey, value: username);
        state = AuthState(user: username);
        return true;
      }
      final ok = await userApi.login(username, password);
      if (ok) {
        await _secureStorage.write(key: _userKey, value: username);
        state = AuthState(user: username);
        return true;
      }
      state = state.copyWith(isLoading: false);
      return false;
    } catch (_) {
      // Fallback to demo if network error
      if (username == 'demo' && password == 'demo') {
        await _secureStorage.write(key: _userKey, value: username);
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
    await _secureStorage.delete(key: _userKey);
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
