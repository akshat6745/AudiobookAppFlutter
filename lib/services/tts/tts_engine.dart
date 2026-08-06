import 'dart:typed_data';

/// Audio produced by a [TtsEngine]: raw bytes plus a format hint so callers
/// know the correct file extension for the cache (`downloads/<id>/<i>.<ext>`).
class TtsAudio {
  const TtsAudio(this.bytes, this.format);

  final Uint8List bytes;

  /// `'mp3'` for the remote (edge-tts / Piper server) engine,
  /// `'wav'` for the on-device sherpa_onnx engine.
  final String format;
}

/// A source of paragraph-level, dual-voice speech audio.
///
/// Implementations are interchangeable: [RemoteTtsEngine] fetches MP3s from the
/// backend (online), [SherpaOnnxTtsEngine] synthesizes WAV on-device (offline).
/// Playback / caching code depends only on this interface, so the two can be
/// swapped transparently (see `lib/providers/tts_engine_provider.dart`).
abstract class TtsEngine {
  /// Whether this engine can run right now — e.g. an on-device model is
  /// installed, or (for the remote engine) the caller has connectivity.
  Future<bool> isAvailable();

  /// Synthesize one paragraph. The paragraph is split internally into narrator
  /// vs. dialogue segments (see [DualVoiceSegmenter]) and each is voiced
  /// accordingly, then concatenated into a single clip — matching the backend
  /// `/tts-dual-voice` contract.
  Future<TtsAudio> synthParagraph({
    required String text,
    required String paragraphVoice,
    required String dialogueVoice,
  });

  /// Release native resources (no-op for the remote engine).
  Future<void> dispose() async {}
}
