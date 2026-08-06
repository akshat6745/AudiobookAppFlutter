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

    test('catalog matches the installed kokoro-en-v0_19 model (28 English '
        'voices, sids 0-27)', () {
      expect(KokoroVoices.all.length, 28);
      final sids = KokoroVoices.all.map((v) => v.sid).toList()..sort();
      expect(sids, List.generate(28, (i) => i),
          reason: 'sids must be exactly 0..27 with no gaps or out-of-range '
              'values — anything else plays the wrong speaker (or fails) on '
              'the installed model');
      expect(KokoroVoices.all.every((v) => v.language == VoiceLanguage.americanEnglish || v.language == VoiceLanguage.britishEnglish), isTrue);
    });

    test('seeded favorite ids are all real catalog voices', () {
      for (final id in KokoroVoices.defaultFavoriteIds) {
        expect(KokoroVoices.isKokoro(id), isTrue,
            reason: '$id must exist in the catalog to be a valid favorite seed');
      }
    });

    test('every preset references real catalog voices', () {
      for (final preset in KokoroVoices.presets) {
        expect(KokoroVoices.isKokoro(preset.narratorId), isTrue,
            reason: '${preset.id} narratorId ${preset.narratorId} must exist');
        expect(KokoroVoices.isKokoro(preset.dialogueId), isTrue,
            reason: '${preset.id} dialogueId ${preset.dialogueId} must exist');
      }
    });

    test('byId resolves a real voice and returns null for unknown ids', () {
      expect(KokoroVoices.byId('af_heart')?.name, 'Heart');
      expect(KokoroVoices.byId('does-not-exist'), isNull);
    });
  });
}
