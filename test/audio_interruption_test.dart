import 'package:audiobook_app/services/audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  group('decideInterruptionResume', () {
    test('resumes a loaded paragraph — whether paused mid-playback or loaded '
        'during the interruption (it landed between paragraphs)', () {
      // Between paragraphs the player is deliberately paused, so `playing`
      // was false when the interruption began — intent drives the resume.
      expect(
        decideInterruptionResume(
          wantsPlayback: true,
          loadInFlight: false,
          processingState: ProcessingState.ready,
        ),
        InterruptionResumeDecision.resume,
      );
    });

    test('leaves an in-flight paragraph load to start playback itself '
        '(advancing here would skip that paragraph)', () {
      for (final state in ProcessingState.values) {
        expect(
          decideInterruptionResume(
            wantsPlayback: true,
            loadInFlight: true,
            processingState: state,
          ),
          InterruptionResumeDecision.ignore,
          reason: 'processingState=$state',
        );
      }
    });

    test('advances when the source completed and nothing is loading', () {
      expect(
        decideInterruptionResume(
          wantsPlayback: true,
          loadInFlight: false,
          processingState: ProcessingState.completed,
        ),
        InterruptionResumeDecision.advance,
      );
    });

    test('advances when paused with <= 1s remaining in the paragraph '
        '(trailing silence / hardware buffer tail)', () {
      expect(
        decideInterruptionResume(
          wantsPlayback: true,
          loadInFlight: false,
          processingState: ProcessingState.ready,
          position: const Duration(milliseconds: 7300),
          duration: const Duration(milliseconds: 8000),
        ),
        InterruptionResumeDecision.advance,
      );
    });

    test('resumes from start when a short <1s heading was loaded at 0:00 '
        'during an interruption', () {
      expect(
        decideInterruptionResume(
          wantsPlayback: true,
          loadInFlight: false,
          processingState: ProcessingState.ready,
          position: Duration.zero,
          duration: const Duration(milliseconds: 850),
        ),
        InterruptionResumeDecision.resume,
      );
    });

    test('stays paused when the user paused before or during it', () {
      for (final state in ProcessingState.values) {
        expect(
          decideInterruptionResume(
            wantsPlayback: false,
            loadInFlight: false,
            processingState: state,
          ),
          InterruptionResumeDecision.ignore,
          reason: 'processingState=$state',
        );
      }
    });
  });

  group('isNearParagraphEnd', () {
    test('returns true when past midpoint and <= 1s remains', () {
      expect(
        isNearParagraphEnd(
          position: const Duration(milliseconds: 9100),
          duration: const Duration(seconds: 10),
        ),
        isTrue,
      );
      expect(
        isNearParagraphEnd(
          position: const Duration(milliseconds: 9000),
          duration: const Duration(seconds: 10),
        ),
        isTrue,
      );
    });

    test('returns false when more than 1s remains', () {
      expect(
        isNearParagraphEnd(
          position: const Duration(milliseconds: 8500),
          duration: const Duration(seconds: 10),
        ),
        isFalse,
      );
    });

    test('returns false at Duration.zero or before midpoint of short clip', () {
      expect(
        isNearParagraphEnd(
          position: Duration.zero,
          duration: const Duration(milliseconds: 800),
        ),
        isFalse,
      );
      expect(
        isNearParagraphEnd(
          position: const Duration(milliseconds: 300),
          duration: const Duration(milliseconds: 1200),
        ),
        isFalse,
      );
      expect(
        isNearParagraphEnd(
          position: const Duration(milliseconds: 700),
          duration: const Duration(milliseconds: 1200),
        ),
        isTrue,
      );
    });
  });
}
