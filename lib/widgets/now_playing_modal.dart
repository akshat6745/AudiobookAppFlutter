import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_providers.dart';
import '../providers/playback_coordinator.dart';
import '../theme/app_theme.dart';

// FEATURES.md §11
const _voices = [
  'en-US-AvaMultilingualNeural',
  'en-US-ChristopherNeural',
  'en-US-JennyNeural',
  'en-GB-SoniaNeural',
  'en-GB-RyanNeural',
  'en-US-AndrewMultilingualNeural',
  'en-US-EmmaMultilingualNeural',
];

const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

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

enum _VoiceRole { narrator, dialogue }

class _VoiceChips extends ConsumerWidget {
  const _VoiceChips({required this.role});
  final _VoiceRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = role == _VoiceRole.narrator
        ? ref.watch(narratorVoiceProvider)
        : ref.watch(dialogueVoiceProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final v in _voices)
          ChoiceChip(
            label: Text(_shortVoiceName(v)),
            selected: v == current,
            onSelected: (_) => _apply(ref, v),
          ),
      ],
    );
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

String _shortVoiceName(String v) {
  var s = v.replaceFirst(RegExp(r'^en-[A-Z]{2}-'), '');
  s = s
      .replaceFirst('MultilingualNeural', '')
      .replaceFirst('Neural', '');
  return s;
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
