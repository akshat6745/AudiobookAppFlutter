import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tts_engine_provider.dart';

enum TtsModelDownloadStatus { idle, downloading, extracting, installed, error }

class TtsModelDownloadState {
  const TtsModelDownloadState({
    this.status = TtsModelDownloadStatus.idle,
    this.progress = 0,
    this.error,
  });

  final TtsModelDownloadStatus status;

  /// Download fraction (0..1) while [status] is downloading.
  final double progress;
  final String? error;

  bool get isBusy =>
      status == TtsModelDownloadStatus.downloading ||
      status == TtsModelDownloadStatus.extracting;

  TtsModelDownloadState copyWith({
    TtsModelDownloadStatus? status,
    double? progress,
    String? error,
  }) =>
      TtsModelDownloadState(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        error: error,
      );
}

class TtsModelDownloadNotifier extends StateNotifier<TtsModelDownloadState> {
  TtsModelDownloadNotifier(this._ref) : super(const TtsModelDownloadState());

  final Ref _ref;

  Future<void> start() async {
    if (state.isBusy) return;
    state = const TtsModelDownloadState(
      status: TtsModelDownloadStatus.downloading,
    );
    try {
      final manager = _ref.read(ttsModelManagerProvider);
      await manager.downloadAndInstall(
        onProgress: (fraction) => state = state.copyWith(
          status: TtsModelDownloadStatus.downloading,
          progress: fraction,
        ),
        onExtracting: () =>
            state = state.copyWith(status: TtsModelDownloadStatus.extracting),
      );
      state = const TtsModelDownloadState(
        status: TtsModelDownloadStatus.installed,
        progress: 1,
      );
      // Re-evaluate which engine is active now that the model exists.
      _ref.invalidate(ttsModelPathsProvider);
      _ref.invalidate(activeTtsEngineProvider);
    } catch (_) {
      // Keep the message generic; internal details aren't useful to the user.
      state = const TtsModelDownloadState(
        status: TtsModelDownloadStatus.error,
        error: 'Download failed. Check your connection and try again.',
      );
    }
  }

  /// First-launch auto-provision: if the model isn't installed and we're on an
  /// unmetered network, start the download. No-ops otherwise, so we never pull
  /// ~300 MB over cellular, re-trigger while busy, or retry after an error.
  Future<void> maybeAutoStart() async {
    if (state.isBusy || state.status == TtsModelDownloadStatus.error) return;
    final installed = await _ref.read(ttsModelPathsProvider.future);
    if (installed != null) return;

    final results = await Connectivity().checkConnectivity();
    final unmetered = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    if (!unmetered) return;

    await start();
  }
}

final ttsModelDownloadProvider =
    StateNotifierProvider<TtsModelDownloadNotifier, TtsModelDownloadState>(
  (ref) => TtsModelDownloadNotifier(ref),
);
