import 'package:audiobook_app/services/tts/dual_voice_segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DualVoiceSegmenter', () {
    test('plain narration → single narrator segment', () {
      final segs = DualVoiceSegmenter.segment('Just some narration here.');
      expect(segs.length, 1);
      expect(segs.single.isDialogue, isFalse);
      expect(segs.single.text, 'Just some narration here.');
    });

    test('splits curly-quoted dialogue from narration, in order', () {
      final segs = DualVoiceSegmenter.segment(
        'The knight spoke. “Hold the line!” he shouted.',
      );
      expect(segs.map((s) => (s.text, s.isDialogue)).toList(), [
        ('The knight spoke.', false),
        ('Hold the line!', true),
        ('he shouted.', false),
      ]);
    });

    test('recognizes straight double quotes', () {
      final segs = DualVoiceSegmenter.segment('She said "hello" softly.');
      expect(segs.map((s) => (s.text, s.isDialogue)).toList(), [
        ('She said', false),
        ('hello', true),
        ('softly.', false),
      ]);
    });

    test('handles multiple interleaved dialogues', () {
      final segs = DualVoiceSegmenter.segment('“Yes.” A pause. “No.”');
      expect(segs.map((s) => (s.text, s.isDialogue)).toList(), [
        ('Yes.', true),
        ('A pause.', false),
        ('No.', true),
      ]);
    });

    test('replaces scene-break asterisks with spoken text', () {
      final segs = DualVoiceSegmenter.segment('* * *');
      expect(segs.length, 1);
      expect(segs.single.isDialogue, isFalse);
      expect(segs.single.text, 'Asterisk Asterisk Asterisk');
    });

    test('whitespace-only input → no segments', () {
      expect(DualVoiceSegmenter.segment('   \n  '), isEmpty);
    });
  });
}
