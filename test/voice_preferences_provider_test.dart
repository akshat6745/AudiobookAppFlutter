import 'package:audiobook_app/providers/voice_preferences_provider.dart';
import 'package:audiobook_app/services/tts/kokoro_voices.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('favoriteVoiceIdsProvider', () {
    test('seeds the default favorites on first launch', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(favoriteVoiceIdsProvider.notifier).ready;

      expect(
          container.read(favoriteVoiceIdsProvider), KokoroVoices.defaultFavoriteIds);
    });

    test('toggle adds and removes a favorite, persisting across containers',
        () async {
      final container = ProviderContainer();
      await container.read(favoriteVoiceIdsProvider.notifier).ready;

      await container
          .read(favoriteVoiceIdsProvider.notifier)
          .toggle('af_sarah');
      expect(container.read(favoriteVoiceIdsProvider), contains('af_sarah'));
      container.dispose();

      // A fresh container should restore the persisted list, including the
      // newly-added favorite.
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      await container2.read(favoriteVoiceIdsProvider.notifier).ready;
      expect(container2.read(favoriteVoiceIdsProvider), contains('af_sarah'));

      // Toggling again removes it.
      await container2
          .read(favoriteVoiceIdsProvider.notifier)
          .toggle('af_sarah');
      expect(
          container2.read(favoriteVoiceIdsProvider), isNot(contains('af_sarah')));
    });

    test('reorder moves an item to the requested position', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(favoriteVoiceIdsProvider.notifier).ready;

      final before = container.read(favoriteVoiceIdsProvider);
      expect(before, KokoroVoices.defaultFavoriteIds);

      // Move the first favorite (index 0) to the last slot. Per
      // ReorderableListView's convention, `newIndex` is measured *before*
      // the dragged item is removed, so `newIndex == before.length` places
      // it at the very end.
      await container
          .read(favoriteVoiceIdsProvider.notifier)
          .reorder(0, before.length);

      final after = container.read(favoriteVoiceIdsProvider);
      expect(after.last, before[0]);
      expect(after.sublist(0, after.length - 1), before.sublist(1));
    });
  });

  group('recentVoiceIdsProvider', () {
    test('starts empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentVoiceIdsProvider.notifier).ready;
      expect(container.read(recentVoiceIdsProvider), isEmpty);
    });

    test('markUsed pushes to the front and de-duplicates', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentVoiceIdsProvider.notifier).ready;

      final notifier = container.read(recentVoiceIdsProvider.notifier);
      await notifier.markUsed('af_sarah');
      await notifier.markUsed('am_adam');
      await notifier.markUsed('af_sarah'); // re-selecting moves it to front

      expect(container.read(recentVoiceIdsProvider), ['af_sarah', 'am_adam']);
    });

    test('caps at 6 entries', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(recentVoiceIdsProvider.notifier).ready;

      final notifier = container.read(recentVoiceIdsProvider.notifier);
      final ids = KokoroVoices.all.take(8).map((v) => v.id);
      for (final id in ids) {
        await notifier.markUsed(id);
      }

      expect(container.read(recentVoiceIdsProvider).length, 6);
    });

    test('persists across containers', () async {
      final container = ProviderContainer();
      await container.read(recentVoiceIdsProvider.notifier).ready;
      await container.read(recentVoiceIdsProvider.notifier).markUsed('bm_george');
      container.dispose();

      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      await container2.read(recentVoiceIdsProvider.notifier).ready;
      expect(container2.read(recentVoiceIdsProvider), contains('bm_george'));
    });
  });
}
