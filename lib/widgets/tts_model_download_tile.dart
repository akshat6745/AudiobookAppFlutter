import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tts_engine_provider.dart';
import '../providers/tts_model_download_provider.dart';

/// Profile tile to download / manage the on-device Kokoro voice model.
/// Once installed, playback generates audio on-device with no internet.
class TtsModelDownloadTile extends ConsumerWidget {
  const TtsModelDownloadTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(ttsModelPathsProvider).valueOrNull != null;
    final download = ref.watch(ttsModelDownloadProvider);

    final Widget trailing;
    if (installed) {
      trailing = const Icon(Icons.check_circle, color: Colors.green);
    } else if (download.isBusy) {
      trailing = SizedBox(
        width: 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: download.status == TtsModelDownloadStatus.downloading
                  ? download.progress
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              download.status == TtsModelDownloadStatus.extracting
                  ? 'Installing…'
                  : '${(download.progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
    } else {
      trailing = FilledButton.tonal(
        onPressed: () => ref.read(ttsModelDownloadProvider.notifier).start(),
        child: const Text('Download'),
      );
    }

    return Card(
      child: ListTile(
        leading: const Icon(Icons.record_voice_over),
        title: const Text('Offline voice (Kokoro)'),
        subtitle: Text(
          installed
              ? 'Installed — audio is generated on-device, no internet needed.'
              : download.status == TtsModelDownloadStatus.error
                  ? (download.error ?? 'Download failed.')
                  : 'High-quality on-device TTS (~300 MB one-time download).',
        ),
        trailing: trailing,
      ),
    );
  }
}
