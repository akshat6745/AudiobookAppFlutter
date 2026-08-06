import 'package:audiobook_app/services/tts/kokoro_voices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KokoroVoices', () {
    test('resolves a known voice id to its speaker id', () {
      final sarah = KokoroVoices.all.firstWhere((v) => v.id == 'af_sarah');
      expect(KokoroVoices.sidFor('af_sarah', fallback: 99), sarah.sid);
    });

    test('falls back for unknown / legacy edge voice names', () {
      expect(
        KokoroVoices.sidFor('en-US-AvaMultilingualNeural', fallback: 7),
        7,
      );
    });

    test('labelFor returns the id itself for unknown voices', () {
      expect(KokoroVoices.labelFor('does-not-exist'), 'does-not-exist');
    });

    test('ids and sids are unique across the catalog', () {
      final ids = KokoroVoices.all.map((v) => v.id).toSet();
      final sids = KokoroVoices.all.map((v) => v.sid).toSet();
      expect(ids.length, KokoroVoices.all.length);
      expect(sids.length, KokoroVoices.all.length);
    });

    test('defaults are real catalog voices', () {
      expect(KokoroVoices.isKokoro(KokoroVoices.defaultNarratorId), isTrue);
      expect(KokoroVoices.isKokoro(KokoroVoices.defaultDialogueId), isTrue);
    });
  });
}
