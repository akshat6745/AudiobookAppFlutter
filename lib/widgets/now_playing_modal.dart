import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_providers.dart';
import '../providers/playback_coordinator.dart';
import '../providers/tts_engine_provider.dart';
import '../providers/voice_preferences_provider.dart';
import '../services/tts/kokoro_voices.dart';
import '../services/tts/remote_tts_engine.dart';
import '../services/tts/sherpa_onnx_tts_engine.dart';
import '../theme/app_theme.dart';
import 'online_voice_picker.dart';
import 'tts_mode_selector.dart';
import 'voice_picker.dart';

const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// Whether the *actually resolved* engine (not just the model-installed
/// check) is on-device Kokoro — this is what voice UI should branch on, so
/// it always matches what will really generate the audio.
bool _kokoroResolved(WidgetRef ref) =>
    ref.watch(activeTtsEngineProvider).valueOrNull is SherpaOnnxTtsEngine;

Future<void> showNowPlayingModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const NowPlayingModal(),
  );
}

class NowPlayingModal extends ConsumerWidget {
  const NowPlayingModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const _Header(),
            const SizedBox(height: 12),
            const _ParagraphCard(),
            const SizedBox(height: 24),
            const _TransportRow(),
            const SizedBox(height: 24),
            const _SectionLabel(label: 'Playback speed'),
            const SizedBox(height: 8),
            const _SpeedChips(),
            const SizedBox(height: 20),
            const _PresetsRow(),
            const _SectionLabel(label: 'Voice generation'),
            const SizedBox(height: 8),
            const TtsModeSelector(),
            const SizedBox(height: 6),
            const _EngineStatusBanner(),
            const SizedBox(height: 20),
            const _SectionLabel(label: 'Narrator voice'),
            const SizedBox(height: 8),
            const _VoiceChips(role: _VoiceRole.narrator),
            const SizedBox(height: 20),
            const _SectionLabel(label: 'Dialogue voice'),
            const SizedBox(height: 8),
            const _VoiceChips(role: _VoiceRole.dialogue),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioStateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.novel?.title ?? 'Now Playing',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          state.chapter?.chapterTitle ?? '',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (state.currentIndex != null) ...[
          const SizedBox(height: 2),
          Text(
            'Paragraph ${state.currentIndex}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _ParagraphCard extends ConsumerWidget {
  const _ParagraphCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioStateProvider);
    final idx = state.currentIndex;
    final text = (idx != null && idx < state.content.length)
        ? state.content[idx]
        : 'Nothing playing';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, height: 1.55),
      ),
    );
  }
}

class _TransportRow extends ConsumerWidget {
  const _TransportRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final coord = ref.read(playbackCoordinatorProvider);
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (_, snap) {
        final playing = snap.data?.playing ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_previous),
              onPressed: coord.playPrevious,
            ),
            const SizedBox(width: 8),
            IconButton(
              iconSize: 64,
              icon: Icon(
                playing
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                color: AppColors.primary,
              ),
              onPressed: coord.toggle,
            ),
            const SizedBox(width: 8),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_next),
              onPressed: coord.playNext,
            ),
            const SizedBox(width: 8),
            IconButton(
              iconSize: 36,
              tooltip: 'Stop and close',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () async {
                await coord.stop();
                // Dismiss the modal once playback is fully torn down so
                // the user lands back on whatever screen was beneath.
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
          ],
        );
      },
    );
  }
}

/// Explains what "Auto" actually resolved to right now, and confirms Online/
/// Offline are doing what the user picked. Auto is the one mode whose
/// behavior isn't self-evident from the toggle alone (it silently falls back
/// to online when the on-device model isn't installed), so this makes that
/// resolution visible instead of leaving the user to guess why voice
/// selection looks different than expected.
class _EngineStatusBanner extends ConsumerWidget {
  const _EngineStatusBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(ttsModeProvider);
    final savedReady =
        ref.watch(savedChapterReadyProvider).valueOrNull ?? false;
    final engineAsync = ref.watch(activeTtsEngineProvider);

    return engineAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (engine) {
        final isOnline = engine is RemoteTtsEngine;
        final IconData icon;
        final String text;
        switch (mode) {
          case TtsMode.online:
            icon = Icons.cloud_outlined;
            text = 'Online — generated by the backend.';
          case TtsMode.offline when !isOnline:
            icon = Icons.download_done;
            text = 'Offline — generated on-device, no network used.';
          case TtsMode.offline:
            icon = Icons.cloud_outlined;
            text = "Offline selected, but the on-device model isn't "
                'downloaded yet — using the backend for now.';
          case TtsMode.auto when isOnline:
            icon = Icons.auto_awesome;
            text = 'Auto — using online voices (on-device model not '
                'installed).';
          case TtsMode.auto:
            icon = Icons.auto_awesome;
            text = "Auto — using the on-device model since it's installed.";
          case TtsMode.saved when savedReady:
            icon = Icons.library_music_outlined;
            text = 'R2 — playing the recorded chapter audio.';
          case TtsMode.saved:
            icon = Icons.auto_awesome;
            text = "This chapter isn't fully recorded — using Auto.";
        }
        return Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpeedChips extends ConsumerWidget {
  const _SpeedChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (_, snap) {
        final current = snap.data?.speed ?? 1.0;
        return Wrap(
          spacing: 8,
          children: [
            for (final s in _speeds)
              ChoiceChip(
                label: Text('${s}x'),
                selected: (current - s).abs() < 0.01,
                onSelected: (_) =>
                    ref.read(playbackCoordinatorProvider).setSpeed(s),
              ),
          ],
        );
      },
    );
  }
}

/// Quick-select narrator+dialogue voice pairings (only meaningful when the
/// on-device Kokoro catalog is active — the remote voice list has no
/// curated pairings).
class _PresetsRow extends ConsumerWidget {
  const _PresetsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_kokoroResolved(ref)) return const SizedBox.shrink();

    final narrator = ref.watch(narratorVoiceProvider);
    final dialogue = ref.watch(dialogueVoiceProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(label: 'Quick presets'),
          const SizedBox(height: 8),
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: KokoroVoices.presets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final preset = KokoroVoices.presets[i];
                final isActive =
                    preset.narratorId == narrator && preset.dialogueId == dialogue;
                return _PresetChip(
                  preset: preset,
                  isActive: isActive,
                  onTap: () => _applyPreset(ref, preset),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyPreset(WidgetRef ref, VoicePreset preset) async {
    final cache = ref.read(audioCacheProvider);
    ref.read(narratorVoiceProvider.notifier).state = preset.narratorId;
    ref.read(dialogueVoiceProvider.notifier).state = preset.dialogueId;
    await cache.updateVoices(preset.narratorId, preset.dialogueId);
    final recents = ref.read(recentVoiceIdsProvider.notifier);
    await recents.markUsed(preset.narratorId);
    await recents.markUsed(preset.dialogueId);
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.isActive,
    required this.onTap,
  });

  final VoicePreset preset;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              preset.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              preset.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

enum _VoiceRole { narrator, dialogue }

class _VoiceChips extends ConsumerWidget {
  const _VoiceChips({required this.role});
  final _VoiceRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = role == _VoiceRole.narrator
        ? ref.watch(narratorVoiceProvider)
        : ref.watch(dialogueVoiceProvider);
    final title =
        role == _VoiceRole.narrator ? 'Narrator voice' : 'Dialogue voice';

    // Both catalogs (50+ Kokoro voices, 47 online voices) are too big for a
    // wall of chips — open a searchable, grouped picker either way, backed
    // by whichever catalog actually matches the resolved engine.
    if (_kokoroResolved(ref)) {
      final label = KokoroVoices.isKokoro(current)
          ? KokoroVoices.labelFor(current)
          : '${KokoroVoices.labelFor(role == _VoiceRole.narrator ? KokoroVoices.defaultNarratorId : KokoroVoices.defaultDialogueId)} (default)';
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => showVoicePicker(
            context: context,
            title: title,
            currentVoiceId: current,
            onSelected: (id) => _apply(ref, id),
          ),
          icon: const Icon(Icons.record_voice_over, size: 18),
          label: Text(label),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => showOnlineVoicePicker(
          context: context,
          title: title,
          currentVoiceId: current,
          onSelected: (id) => _apply(ref, id),
        ),
        icon: const Icon(Icons.record_voice_over, size: 18),
        label: Text(_onlineVoiceLabel(current)),
      ),
    );
  }

  /// Short display name for an online voice id, e.g.
  /// `en-US-AvaMultilingualNeural` → `Ava`. Falls back to the raw id for a
  /// stale/unrecognized value (e.g. right after switching from offline,
  /// before the reconciliation in main.dart has applied — see
  /// `_reconcileVoicesForEngine`).
  String _onlineVoiceLabel(String voiceId) {
    final match = RegExp(r'^en-[A-Z]{2}-(\w+?)(Multilingual)?Neural$')
        .firstMatch(voiceId);
    return match?.group(1) ?? voiceId;
  }

  Future<void> _apply(WidgetRef ref, String voice) async {
    final cache = ref.read(audioCacheProvider);
    final narratorNotifier = ref.read(narratorVoiceProvider.notifier);
    final dialogueNotifier = ref.read(dialogueVoiceProvider.notifier);

    final newNarrator =
        role == _VoiceRole.narrator ? voice : narratorNotifier.state;
    final newDialogue =
        role == _VoiceRole.dialogue ? voice : dialogueNotifier.state;

    if (role == _VoiceRole.narrator) narratorNotifier.state = voice;
    if (role == _VoiceRole.dialogue) dialogueNotifier.state = voice;

    await cache.updateVoices(newNarrator, newDialogue);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
    );
  }
}
