import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tts/remote_tts_engine.dart';
import '../services/tts/sherpa_onnx_tts_engine.dart';
import '../services/tts/tts_engine.dart';
import '../services/tts/tts_model_manager.dart';

/// Manages the on-device Kokoro model (download / install / locate).
final ttsModelManagerProvider =
    Provider<TtsModelManager>((ref) => TtsModelManager.kokoro());

/// Installed on-device model paths, or null if not yet downloaded.
/// `invalidate` this after a successful download to flip the active engine.
final ttsModelPathsProvider = FutureProvider<TtsModelPaths?>((ref) async {
  return ref.watch(ttsModelManagerProvider).installedPaths();
});

/// The online engine (backend `/tts-dual-voice`, MP3). Always constructible.
final remoteTtsEngineProvider = Provider<TtsEngine>((ref) => RemoteTtsEngine());

/// The engine playback should use: **on-device Kokoro when its model is
/// installed**, otherwise the remote engine. Playback/caching code depends only
/// on [TtsEngine], so switching is transparent.
///
/// NOTE: selects by model availability, not connectivity. Layer a
/// `connectivity_plus` check on top for "on-device offline, remote only when
/// online" (see OFFLINE_FIRST_ARCHITECTURE.md §7).
final activeTtsEngineProvider = FutureProvider<TtsEngine>((ref) async {
  final paths = await ref.watch(ttsModelPathsProvider.future);
  if (paths != null) {
    return SherpaOnnxTtsEngine(paths: paths);
  }
  return ref.watch(remoteTtsEngineProvider);
});
