import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/online_voice.dart';
import '../providers/online_voices_provider.dart';
import '../providers/voice_preferences_provider.dart';
import '../services/tts/remote_tts_engine.dart';
import '../theme/app_theme.dart';

enum _GenderFilter { all, female, male }

const _previewSentence =
    'The old lighthouse keeper watched the storm roll in from the sea.';

/// Same shape as `showVoicePicker` (the on-device Kokoro picker), but backed
/// by the backend's `/tts-voices` catalog. Kept as a separate widget rather
/// than generalizing the Kokoro picker — the two voice namespaces (Kokoro
/// ids vs. edge-tts short names) and their metadata (accent/personality vs.
/// language) differ enough that sharing one widget would mean threading an
/// abstraction through code that's currently simple and working.
Future<void> showOnlineVoicePicker({
  required BuildContext context,
  required String title,
  required String currentVoiceId,
  required ValueChanged<String> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _OnlineVoicePickerSheet(
      title: title,
      currentVoiceId: currentVoiceId,
      onSelected: onSelected,
    ),
  );
}

class _OnlineVoicePickerSheet extends ConsumerStatefulWidget {
  const _OnlineVoicePickerSheet({
    required this.title,
    required this.currentVoiceId,
    required this.onSelected,
  });

  final String title;
  final String currentVoiceId;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<_OnlineVoicePickerSheet> createState() =>
      _OnlineVoicePickerSheetState();
}

class _OnlineVoicePickerSheetState
    extends ConsumerState<_OnlineVoicePickerSheet> {
  String _query = '';
  _GenderFilter _genderFilter = _GenderFilter.all;
  String? _accentFilter;

  // Synthesizes previews via the online engine directly, regardless of which
  // engine is actually active — this picker is for browsing edge-tts voices,
  // so previews must always come from the backend, not on-device Kokoro.
  final RemoteTtsEngine _previewEngine = RemoteTtsEngine();
  final AudioPlayer _previewPlayer = AudioPlayer();
  final Map<String, String> _sampleCache = {};
  StreamSubscription<PlayerState>? _playerSub;
  String? _playingVoiceId;
  String? _loadingVoiceId;

  @override
  void initState() {
    super.initState();
    _playerSub = _previewPlayer.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) {
        setState(() => _playingVoiceId = null);
      }
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _previewPlayer.dispose();
    super.dispose();
  }

  void _select(OnlineVoice v) {
    ref.read(recentVoiceIdsProvider.notifier).markUsed(v.shortName);
    widget.onSelected(v.shortName);
    Navigator.of(context).pop();
  }

  Future<void> _toggleSample(OnlineVoice v) async {
    if (_playingVoiceId == v.shortName) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _playingVoiceId = null);
      return;
    }
    if (_loadingVoiceId != null) return;
    setState(() => _loadingVoiceId = v.shortName);
    try {
      var path = _sampleCache[v.shortName];
      if (path == null) {
        final audio = await _previewEngine.synthParagraph(
          text: _previewSentence,
          paragraphVoice: v.shortName,
          dialogueVoice: v.shortName,
        );
        final dir = await getTemporaryDirectory();
        final samplesDir = Directory(p.join(dir.path, 'voice_samples'));
        if (!samplesDir.existsSync()) samplesDir.createSync(recursive: true);
        path = p.join(samplesDir.path, '${v.shortName}.${audio.format}');
        await File(path).writeAsBytes(audio.bytes);
        _sampleCache[v.shortName] = path;
      }
      if (!mounted) return;
      await _previewPlayer.setFilePath(path);
      await _previewPlayer.play();
      if (mounted) setState(() => _playingVoiceId = v.shortName);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play voice sample')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingVoiceId = null);
    }
  }

  bool _matches(OnlineVoice v) {
    if (_genderFilter == _GenderFilter.female && !v.isFemale) return false;
    if (_genderFilter == _GenderFilter.male && v.isFemale) return false;
    if (_accentFilter != null && v.accentLabel != _accentFilter) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return v.displayName.toLowerCase().contains(q) ||
        v.accentLabel.toLowerCase().contains(q) ||
        v.styleLabel.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final voicesAsync = ref.watch(onlineVoicesProvider);
    final favoriteIds = ref.watch(favoriteVoiceIdsProvider);
    final recentIds = ref.watch(recentVoiceIdsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: voicesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load online voices: $e'),
              ),
            ),
            data: (all) {
              final accents = all.map((v) => v.accentLabel).toSet().toList()
                ..sort();
              final filtered = all.where(_matches).toList(growable: false);
              final filteredIds = filtered.map((v) => v.shortName).toSet();
              final byId = {for (final v in all) v.shortName: v};

              final favorites = [
                for (final id in favoriteIds)
                  if (byId[id] != null && filteredIds.contains(id)) byId[id]!,
              ];
              final recents = [
                for (final id in recentIds)
                  if (!favoriteIds.contains(id) &&
                      byId[id] != null &&
                      filteredIds.contains(id))
                    byId[id]!,
              ];
              final byGender = <bool, List<OnlineVoice>>{};
              for (final v in filtered) {
                (byGender[v.isFemale] ??= <OnlineVoice>[]).add(v);
              }

              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search voice, accent, or style…',
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _GenderChip(
                          label: 'All',
                          selected: _genderFilter == _GenderFilter.all,
                          onTap: () =>
                              setState(() => _genderFilter = _GenderFilter.all),
                        ),
                        const SizedBox(width: 6),
                        _GenderChip(
                          label: 'Female',
                          selected: _genderFilter == _GenderFilter.female,
                          onTap: () => setState(
                              () => _genderFilter = _GenderFilter.female),
                        ),
                        const SizedBox(width: 6),
                        _GenderChip(
                          label: 'Male',
                          selected: _genderFilter == _GenderFilter.male,
                          onTap: () =>
                              setState(() => _genderFilter = _GenderFilter.male),
                        ),
                        const Spacer(),
                        DropdownButton<String?>(
                          value: _accentFilter,
                          hint: const Text('Accent'),
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All accents')),
                            for (final a in accents)
                              DropdownMenuItem(value: a, child: Text(a)),
                          ],
                          onChanged: (v) => setState(() => _accentFilter = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tap ▶ to hear: "$_previewSentence"',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No voices match'))
                        : ListView(
                            controller: scrollController,
                            children: [
                              if (favorites.isNotEmpty) ...[
                                _SectionHeader('FAVORITES'),
                                for (final v in favorites)
                                  _OnlineVoiceRow(
                                    voice: v,
                                    isCurrent: v.shortName == widget.currentVoiceId,
                                    isFavorite: true,
                                    isPlaying: _playingVoiceId == v.shortName,
                                    isLoadingSample: _loadingVoiceId == v.shortName,
                                    onTap: () => _select(v),
                                    onToggleFavorite: () => ref
                                        .read(favoriteVoiceIdsProvider.notifier)
                                        .toggle(v.shortName),
                                    onToggleSample: () => _toggleSample(v),
                                  ),
                              ],
                              if (recents.isNotEmpty) ...[
                                _SectionHeader('RECENTLY USED'),
                                for (final v in recents)
                                  _OnlineVoiceRow(
                                    voice: v,
                                    isCurrent: v.shortName == widget.currentVoiceId,
                                    isFavorite: false,
                                    isPlaying: _playingVoiceId == v.shortName,
                                    isLoadingSample: _loadingVoiceId == v.shortName,
                                    onTap: () => _select(v),
                                    onToggleFavorite: () => ref
                                        .read(favoriteVoiceIdsProvider.notifier)
                                        .toggle(v.shortName),
                                    onToggleSample: () => _toggleSample(v),
                                  ),
                              ],
                              for (final isFemale in const [true, false])
                                if ((byGender[isFemale] ?? const []).isNotEmpty) ...[
                                  _SectionHeader(isFemale ? 'FEMALE' : 'MALE'),
                                  for (final v in byGender[isFemale]!)
                                    _OnlineVoiceRow(
                                      voice: v,
                                      isCurrent:
                                          v.shortName == widget.currentVoiceId,
                                      isFavorite: favoriteIds.contains(v.shortName),
                                      isPlaying: _playingVoiceId == v.shortName,
                                      isLoadingSample:
                                          _loadingVoiceId == v.shortName,
                                      onTap: () => _select(v),
                                      onToggleFavorite: () => ref
                                          .read(favoriteVoiceIdsProvider.notifier)
                                          .toggle(v.shortName),
                                      onToggleSample: () => _toggleSample(v),
                                    ),
                                ],
                              const SizedBox(height: 24),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _OnlineVoiceRow extends StatelessWidget {
  const _OnlineVoiceRow({
    required this.voice,
    required this.isCurrent,
    required this.isFavorite,
    required this.isPlaying,
    required this.isLoadingSample,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onToggleSample,
  });

  final OnlineVoice voice;
  final bool isCurrent;
  final bool isFavorite;
  final bool isPlaying;
  final bool isLoadingSample;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleSample;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        voice.isFemale ? Icons.woman : Icons.man,
        color: AppColors.textMuted,
      ),
      title: Text(voice.displayName),
      subtitle: Text(
        voice.styleLabel.isEmpty
            ? voice.accentLabel
            : '${voice.accentLabel} · ${voice.styleLabel}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      selected: isCurrent,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoadingSample)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: Icon(
                isPlaying ? Icons.stop_circle : Icons.play_circle_outline,
              ),
              tooltip: isPlaying ? 'Stop sample' : 'Play sample',
              onPressed: onToggleSample,
            ),
          IconButton(
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? AppColors.accent : AppColors.textMuted,
            ),
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            onPressed: onToggleFavorite,
          ),
          if (isCurrent)
            const Icon(Icons.check_circle, color: AppColors.primary)
          else
            const SizedBox(width: 24),
        ],
      ),
    );
  }
}
