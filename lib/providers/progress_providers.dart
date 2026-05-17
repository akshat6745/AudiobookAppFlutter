import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/user_api.dart';
import 'auth_providers.dart';

/// Map of novelSlug -> lastChapterRead.
///
/// Source of truth: `userApi.getUserProgress` (server). Local state is a
/// short-lived cache that gets refreshed:
///   * once on construction (cold start),
///   * when callers explicitly request a refresh (screen open, app resume),
///   * after a successful `updateProgress` (so optimistic local writes stay
///     in sync with the server's authoritative ordering).
///
/// Calls are throttled so rapid screen transitions / navigation events don't
/// flood the backend. Callers can pass `force: true` to bypass the throttle
/// (e.g., explicit pull-to-refresh).
class ProgressNotifier extends StateNotifier<Map<String, int>> {
  ProgressNotifier(this._username) : super(const {}) {
    if (_username != null) {
      // Cold-start fetch — bypass throttle so the first paint after sign-in
      // shows authoritative progress without waiting for a screen event.
      refresh(force: true);
    }
  }

  final String? _username;
  DateTime? _lastFullRefreshAt;
  final Map<String, DateTime> _lastNovelRefreshAt = {};
  Future<void>? _inFlightFullRefresh;

  /// Minimum interval between full-list refreshes, unless `force: true`.
  /// Picked to keep the chapter list / novel list reactive without
  /// hammering the backend during fast tab switches.
  static const _fullRefreshThrottle = Duration(seconds: 10);
  static const _novelRefreshThrottle = Duration(seconds: 5);

  Future<void> refresh({bool force = false}) async {
    final user = _username;
    if (user == null) return;

    if (!force) {
      final last = _lastFullRefreshAt;
      if (last != null &&
          DateTime.now().difference(last) < _fullRefreshThrottle) {
        return;
      }
    }

    // De-dupe concurrent refreshes — multiple screens opening at once
    // would otherwise issue parallel identical requests.
    final inFlight = _inFlightFullRefresh;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _inFlightFullRefresh = completer.future;
    try {
      final list = await userApi.getUserProgress(user);
      final map = <String, int>{};
      for (final p in list) {
        map[p.novelName] = p.lastChapterRead;
      }
      if (!mounted) return;
      state = map;
      _lastFullRefreshAt = DateTime.now();
    } catch (_) {
      // Silent failure — server progress is best-effort.
    } finally {
      _inFlightFullRefresh = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Refresh a single novel's progress. Cheaper than `refresh()` when
  /// only the chapter-list page needs an up-to-date "last read" badge.
  Future<void> refreshNovel(String novelSlug, {bool force = false}) async {
    final user = _username;
    if (user == null) return;

    if (!force) {
      final last = _lastNovelRefreshAt[novelSlug];
      if (last != null &&
          DateTime.now().difference(last) < _novelRefreshThrottle) {
        return;
      }
    }

    final progress = await userApi.getNovelProgress(
      username: user,
      novelSlug: novelSlug,
    );
    _lastNovelRefreshAt[novelSlug] = DateTime.now();
    if (!mounted) return;
    if (progress == null) return;

    // Merge into state — only update if the server value is newer/higher
    // OR if we don't have a value yet. Avoids clobbering optimistic
    // updates from `updateProgress` if the server lags behind.
    final existing = state[novelSlug];
    if (existing == null || progress.lastChapterRead >= existing) {
      state = {...state, novelSlug: progress.lastChapterRead};
    }
  }

  Future<void> updateProgress(String novelSlug, int chapterNumber) async {
    final user = _username;
    if (user == null) return;
    // Optimistic — UI updates immediately; reconcile on next refresh.
    state = {...state, novelSlug: chapterNumber};
    try {
      await userApi.saveProgress(
        username: user,
        novelSlug: novelSlug,
        lastChapterRead: chapterNumber,
      );
    } catch (_) {
      // Persist failure is silent (FEATURES.md §13). The next refresh
      // will surface the server's authoritative value.
    }
  }
}

final progressProvider =
    StateNotifierProvider<ProgressNotifier, Map<String, int>>((ref) {
  final user = ref.watch(authProvider).user;
  return ProgressNotifier(user);
});
