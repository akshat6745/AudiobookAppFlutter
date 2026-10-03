import 'package:audiobook_app/services/audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  group('decideInterruptionResume', () {
    test(
      'resumes a loaded paragraph — whether paused mid-playback or loaded '
      'during the interruption (it landed between paragraphs)',
      () {
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
      },
    );

    test(
      'leaves an in-flight paragraph load to start playback itself '
      '(advancing here would skip that paragraph)',
      () {
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
      },
    );

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
}
