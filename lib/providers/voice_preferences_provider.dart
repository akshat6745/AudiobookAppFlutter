import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage.dart';
import '../services/tts/kokoro_voices.dart';

/// Favorite voice ids, in user-chosen order. Persisted to [Storage] and
/// seeded with [KokoroVoices.defaultFavoriteIds] on first launch so the
/// "Favorites" section in the voice picker is never empty by default.
class FavoriteVoicesNotifier extends StateNotifier<List<String>> {
  FavoriteVoicesNotifier() : super(KokoroVoices.defaultFavoriteIds) {
    ready = _restore();
  }

  /// Resolves once the persisted list (or the seed, on first launch) has
  /// been loaded. Tests await this instead of guessing a delay; production
  /// code doesn't need it — [state] already starts at a sensible default.
  late final Future<void> ready;

  Future<void> _restore() async {
    final raw = await Storage.getString(StorageKeys.favoriteVoiceIds);
    if (raw == null) {
      // First launch — persist the seed so it stays stable even if the
      // seed constant changes in a future release.
      await _persist(state);
      return;
    }
    final ids = raw.split(',').where((s) => s.isNotEmpty).toList();
    state = ids;
  }

  Future<void> _persist(List<String> ids) =>
      Storage.setString(StorageKeys.favoriteVoiceIds, ids.join(','));

  bool isFavorite(String id) => state.contains(id);

  Future<void> toggle(String id) async {
    final next = List<String>.from(state);
    if (!next.remove(id)) next.add(id);
    state = next;
    await _persist(next);
  }

  /// Reorder within the favorites list (drag-to-reorder in the picker).
  /// Uses `ReorderableListView`'s index convention (`newIndex` is the
  /// target index *before* the dragged item is removed).
  Future<void> reorder(int oldIndex, int newIndex) async {
    final next = List<String>.from(state);
    if (oldIndex < newIndex) newIndex -= 1;
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    state = next;
    await _persist(next);
  }
}

final favoriteVoiceIdsProvider =
    StateNotifierProvider<FavoriteVoicesNotifier, List<String>>(
  (_) => FavoriteVoicesNotifier(),
);

/// Most-recently-selected voice ids, newest first. Persisted, capped at
/// [_maxEntries].
class RecentVoicesNotifier extends StateNotifier<List<String>> {
  RecentVoicesNotifier() : super(const []) {
    ready = _restore();
  }

  /// Resolves once any persisted recents have been loaded (see
  /// [FavoriteVoicesNotifier.ready] for why tests use this).
  late final Future<void> ready;

  static const _maxEntries = 6;

  Future<void> _restore() async {
    final raw = await Storage.getString(StorageKeys.recentVoiceIds);
    if (raw == null) return;
    state = raw.split(',').where((s) => s.isNotEmpty).toList();
  }

  Future<void> markUsed(String id) async {
    final next = [id, ...state.where((v) => v != id)].take(_maxEntries).toList();
    state = next;
    await Storage.setString(StorageKeys.recentVoiceIds, next.join(','));
  }
}

final recentVoiceIdsProvider =
    StateNotifierProvider<RecentVoicesNotifier, List<String>>(
  (_) => RecentVoicesNotifier(),
);
