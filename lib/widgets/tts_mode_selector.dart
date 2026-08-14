import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tts_engine_provider.dart';

/// Profile screen control letting the user force online or offline voice
/// generation, or leave it on [TtsMode.auto] (prefer on-device once the
/// Kokoro model is installed, otherwise use the backend).
class TtsModeSelector extends ConsumerWidget {
  const TtsModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(ttsModeProvider);
    final modelInstalled =
        ref.watch(ttsModelPathsProvider).valueOrNull != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<TtsMode>(
          segments: const [
            ButtonSegment(
              value: TtsMode.auto,
              label: Text('Auto'),
              icon: Icon(Icons.auto_awesome),
            ),
            ButtonSegment(
              value: TtsMode.offline,
              label: Text('Offline'),
              icon: Icon(Icons.download_done),
            ),
            ButtonSegment(
              value: TtsMode.online,
              label: Text('Online'),
              icon: Icon(Icons.cloud_outlined),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) =>
              ref.read(ttsModeProvider.notifier).select(selection.first),
        ),
        const SizedBox(height: 6),
        Text(
          _description(mode, modelInstalled),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  String _description(TtsMode mode, bool modelInstalled) {
    switch (mode) {
      case TtsMode.online:
        return 'Always uses the deployed backend, even if the offline '
            'model is installed.';
      case TtsMode.offline:
        return modelInstalled
            ? 'Always generates on-device — no network used.'
            : 'Offline model not downloaded yet — using the backend until '
                'it is.';
      case TtsMode.auto:
        return 'Uses the on-device model when installed, otherwise the '
            'backend.';
    }
  }
}
