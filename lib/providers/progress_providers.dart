import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/user_api.dart';
import 'auth_providers.dart';

/// Map of novelSlug -> lastChapterRead.
class ProgressNotifier extends StateNotifier<Map<String, int>> {
  ProgressNotifier(this._username) : super(const {}) {
    if (_username != null) _refresh();
  }

  final String? _username;

  Future<void> _refresh() async {
    final user = _username;
    if (user == null) return;
    try {
      final list = await userApi.getUserProgress(user);
      final map = <String, int>{};
      for (final p in list) {
        map[p.novelName] = p.lastChapterRead;
      }
      state = map;
    } catch (_) {
      // Silent failure — not critical
    }
  }

  Future<void> updateProgress(String novelSlug, int chapterNumber) async {
    final user = _username;
    if (user == null) return;
    // Optimistic
    state = {...state, novelSlug: chapterNumber};
    try {
      await userApi.saveProgress(
        username: user,
        novelSlug: novelSlug,
        lastChapterRead: chapterNumber,
      );
    } catch (_) {}
  }

  Future<void> refresh() => _refresh();
}

final progressProvider =
    StateNotifierProvider<ProgressNotifier, Map<String, int>>((ref) {
  final user = ref.watch(authProvider).user;
  return ProgressNotifier(user);
});
