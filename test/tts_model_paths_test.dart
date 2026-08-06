import 'package:audiobook_app/services/tts/sherpa_onnx_tts_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TtsModelPaths (kokoro-en-v0_19)', () {
    const dir = '/data/app/models/kokoro/kokoro-en-v0_19';
    late TtsModelPaths paths;

    setUpAll(() {
      paths = const TtsModelPaths(dir);
    });

    test('kokoroModel points to model.onnx', () {
      expect(paths.kokoroModel, '$dir/model.onnx');
    });

    test('kokoroVoices points to voices.bin', () {
      expect(paths.kokoroVoices, '$dir/voices.bin');
    });

    test('tokens points to tokens.txt', () {
      expect(paths.tokens, '$dir/tokens.txt');
    });

    test('espeakData points to espeak-ng-data', () {
      expect(paths.espeakData, '$dir/espeak-ng-data');
    });

    test('dictDir returns empty string when dict/ dir is absent (en-only model)', () {
      // kokoro-en-v0_19 has no dict/ directory; TtsModelPaths returns '' so
      // sherpa-onnx skips the validation path. In CI there is no real model dir.
      expect(paths.dictDir, isEmpty);
    });

    test('lexicon returns empty string when lexicon file is absent (en-only model)', () {
      // kokoro-en-v0_19 uses espeak directly, no lexicon file.
      // Returns '' so sherpa-onnx skips FileExists() validation.
      expect(paths.lexicon, isEmpty);
    });

    test('all required files have distinct paths', () {
      final allPaths = [
        paths.kokoroModel,
        paths.kokoroVoices,
        paths.tokens,
        paths.espeakData,
      ];
      expect(allPaths.toSet().length, allPaths.length,
          reason: 'all resource paths should be distinct');
    });
  });
}
