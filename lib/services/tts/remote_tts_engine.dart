import '../tts_api.dart';
import 'tts_engine.dart';

/// Online engine — fetches dual-voice MP3s from the backend `/tts-dual-voice`
/// endpoint. This is today's behavior, wrapped behind [TtsEngine] so it can be
/// used as the online fallback / for voice parity with the deployed website.
class RemoteTtsEngine extends TtsEngine {
  RemoteTtsEngine([TtsApi? api]) : _api = api ?? ttsApi;

  final TtsApi _api;

  /// The backend is reachable-dependent; connectivity is decided by the caller
  /// (see the engine selector provider). Returning true here means "usable when
  /// online" rather than "always ready".
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<TtsAudio> synthParagraph({
    required String text,
    required String paragraphVoice,
    required String dialogueVoice,
  }) async {
    final bytes = await _api.convertDualVoice(
      text: text,
      paragraphVoice: paragraphVoice,
      dialogueVoice: dialogueVoice,
    );
    return TtsAudio(bytes, 'mp3');
  }
}
