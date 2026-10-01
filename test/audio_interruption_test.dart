import 'package:audiobook_app/services/audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  group('decideInterruptionPause', () {
    test('pauses when actively playing mid-paragraph', () {
      expect(
        decideInterruptionPause(
          playing: true,
          processingState: ProcessingState.ready,
        ),
        InterruptionPauseDecision.pause,
      );
    });

    test(
      'pauses when the paragraph already completed right before the '
      'interruption (the <1s-remaining race)',
      () {
        expect(
          decideInterruptionPause(
            playing: false,
            processingState: ProcessingState.completed,
          ),
          InterruptionPauseDecision.pause,
        );
      },
    );

    test('ignores when the user had already manually paused', () {
      expect(
        decideInterruptionPause(
          playing: false,
          processingState: ProcessingState.ready,
        ),
        InterruptionPauseDecision.ignore,
      );
    });
  });

  group('decideInterruptionResume', () {
    test('advances when the paragraph had completed by the time we resume', () {
      expect(
        decideInterruptionResume(
          pausedByInterruption: true,
          processingState: ProcessingState.completed,
        ),
        InterruptionResumeDecision.advance,
      );
    });

    test('resumes when the paragraph is still mid-playback', () {
      expect(
        decideInterruptionResume(
          pausedByInterruption: true,
          processingState: ProcessingState.ready,
        ),
        InterruptionResumeDecision.resume,
      );
    });

    test('ignores when this interruption never paused us', () {
      expect(
        decideInterruptionResume(
          pausedByInterruption: false,
          processingState: ProcessingState.completed,
        ),
        InterruptionResumeDecision.ignore,
      );
    });
  });
}
