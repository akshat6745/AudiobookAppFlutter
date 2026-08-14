import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage.dart';
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
/// Routes through the shared `apiClient` (see `api_client.dart`), so it
/// already follows whatever backend the user picked in the backend picker —
/// no separate wiring needed for that.
final remoteTtsEngineProvider = Provider<TtsEngine>((ref) => RemoteTtsEngine());

/// User-facing choice of which engine to use, exposed as a Profile screen
/// toggle. [auto] preserves the original behavior (prefer on-device once
/// installed, otherwise remote); [offline]/[online] force one side.
enum TtsMode { auto, offline, online }

/// Persists [TtsMode] to [Storage] and restores it on the next launch.
class TtsModeNotifier extends StateNotifier<TtsMode> {
  TtsModeNotifier() : super(TtsMode.auto) {
    ready = _restore();
  }

  /// Resolves once the persisted choice (if any) has been loaded. Tests can
  /// await this instead of guessing a delay; production code doesn't need
  /// to — [state] already starts at a sensible default ([TtsMode.auto]).
  late final Future<void> ready;

  Future<void> _restore() async {
    final raw = await Storage.getString(StorageKeys.ttsMode);
    state = TtsMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => TtsMode.auto,
    );
  }

  Future<void> select(TtsMode mode) async {
    state = mode;
    await Storage.setString(StorageKeys.ttsMode, mode.name);
  }
}

final ttsModeProvider =
    StateNotifierProvider<TtsModeNotifier, TtsMode>((_) => TtsModeNotifier());

/// The engine playback should use, honoring [ttsModeProvider]:
///   * [TtsMode.online]  — always the remote backend, even if the on-device
///     model is installed.
///   * [TtsMode.offline] — the on-device Kokoro engine if its model is
///     installed; falls back to remote if it isn't (nothing to run offline
///     with yet — same escape hatch as [TtsMode.auto]).
///   * [TtsMode.auto]    — prefer on-device once installed, otherwise
///     remote. Original behavior, kept as the default so users who never
///     touch the new toggle see no change.
///
/// Playback/caching code depends only on [TtsEngine], so switching is
/// transparent to the rest of the app either way.
final activeTtsEngineProvider = FutureProvider<TtsEngine>((ref) async {
  final mode = ref.watch(ttsModeProvider);
  if (mode == TtsMode.online) {
    return ref.watch(remoteTtsEngineProvider);
  }
  final paths = await ref.watch(ttsModelPathsProvider.future);
  if (paths != null) {
    return SherpaOnnxTtsEngine(paths: paths);
  }
  return ref.watch(remoteTtsEngineProvider);
});
