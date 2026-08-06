import 'package:connectivity_plus/connectivity_plus.dart';

import '../tts_api.dart';
import 'tts_engine.dart';

/// Online engine — fetches dual-voice MP3s from the backend `/tts-dual-voice`
/// endpoint. This is today's behavior, wrapped behind [TtsEngine] so it can be
/// used as the online fallback / for voice parity with the deployed website.
class RemoteTtsEngine extends TtsEngine {
  RemoteTtsEngine([TtsApi? api, Connectivity? connectivity])
      : _api = api ?? ttsApi,
        _connectivity = connectivity ?? Connectivity();

  final TtsApi _api;
  final Connectivity _connectivity;

  Future<bool> _hasConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Reflects actual reachability now, so callers deciding whether to fall
  /// back to this engine (see `activeTtsEngineProvider`) can tell "no
  /// on-device model and offline" apart from "usable when online".
  @override
  Future<bool> isAvailable() => _hasConnectivity();

  @override
  Future<TtsAudio> synthParagraph({
    required String text,
    required String paragraphVoice,
    required String dialogueVoice,
  }) async {
    // Fail fast instead of letting the caller wait out dio's connect
    // timeout — the paragraph never had a chance to reach the network.
    if (!await _hasConnectivity()) {
      throw const TtsOfflineException();
    }
    final bytes = await _api.convertDualVoice(
      text: text,
      paragraphVoice: paragraphVoice,
      dialogueVoice: dialogueVoice,
    );
    return TtsAudio(bytes, 'mp3');
  }
}
