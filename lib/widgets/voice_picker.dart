import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../providers/tts_engine_provider.dart';
import '../providers/voice_preferences_provider.dart';
import '../services/tts/kokoro_voices.dart';
import '../theme/app_theme.dart';

enum _GenderFilter { all, female, male }

/// Opens a searchable, filterable voice picker with favorites, recently-used,
/// and on-device sample playback. Scales to the full Kokoro catalog without
/// the unusable wall-of-chips the old picker had.
Future<void> showVoicePicker({
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
    builder: (_) => _VoicePickerSheet(
      title: title,
      currentVoiceId: currentVoiceId,
      onSelected: onSelected,
    ),
  );
}

class _VoicePickerSheet extends ConsumerStatefulWidget {
  const _VoicePickerSheet({
    required this.title,
    required this.currentVoiceId,
    required this.onSelected,
  });

  final String title;
  final String currentVoiceId;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<_VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends ConsumerState<_VoicePickerSheet> {
  String _query = '';
  _GenderFilter _genderFilter = _GenderFilter.all;
  VoiceLanguage? _accentFilter;

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

  void _select(KokoroVoice v) {
    ref.read(recentVoiceIdsProvider.notifier).markUsed(v.id);
    widget.onSelected(v.id);
    Navigator.of(context).pop();
  }

  Future<void> _toggleSample(KokoroVoice v) async {
    if (_playingVoiceId == v.id) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _playingVoiceId = null);
      return;
    }
    if (_loadingVoiceId != null) return;
    setState(() => _loadingVoiceId = v.id);
    try {
      var path = _sampleCache[v.id];
      if (path == null) {
        final engine = await ref.read(activeTtsEngineProvider.future);
        final audio = await engine.synthParagraph(
          text: KokoroVoices.previewSentence,
          paragraphVoice: v.id,
          dialogueVoice: v.id,
        );
        final dir = await getTemporaryDirectory();
        final samplesDir = Directory(p.join(dir.path, 'voice_samples'));
        if (!samplesDir.existsSync()) samplesDir.createSync(recursive: true);
        path = p.join(samplesDir.path, '${v.id}.${audio.format}');
        await File(path).writeAsBytes(audio.bytes);
        _sampleCache[v.id] = path;
      }
      if (!mounted) return;
      await _previewPlayer.setFilePath(path);
      await _previewPlayer.play();
      if (mounted) setState(() => _playingVoiceId = v.id);
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

  bool _matchesFilters(KokoroVoice v) {
    if (_genderFilter == _GenderFilter.female && !v.isFemale) return false;
    if (_genderFilter == _GenderFilter.male && v.isFemale) return false;
    if (_accentFilter != null && v.language != _accentFilter) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final favoriteIds = ref.watch(favoriteVoiceIdsProvider);
    final recentIds = ref.watch(recentVoiceIdsProvider);

    final searched = KokoroVoices.search(_query).toSet();
    final filtered =
        searched.where(_matchesFilters).toList(growable: false);

    final favorites = [
      for (final id in favoriteIds)
        if (KokoroVoices.byId(id) != null && searched.contains(KokoroVoices.byId(id)))
          KokoroVoices.byId(id)!,
    ];
    final recents = [
      for (final id in recentIds)
        if (!favoriteIds.contains(id) &&
            KokoroVoices.byId(id) != null &&
            searched.contains(KokoroVoices.byId(id)))
          KokoroVoices.byId(id)!,
    ];

    // Remaining voices grouped by gender (Kokoro has no neutral voices).
    final byGender = <bool, List<KokoroVoice>>{};
    for (final v in filtered) {
      (byGender[v.isFemale] ??= <KokoroVoice>[]).add(v);
    }

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
          child: Column(
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
                    hintText: 'Search voice or accent…',
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
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _FilterChip(
                            label: 'All',
                            selected: _genderFilter == _GenderFilter.all,
                            onTap: () =>
                                setState(() => _genderFilter = _GenderFilter.all),
                          ),
                          _FilterChip(
                            label: 'Female',
                            selected: _genderFilter == _GenderFilter.female,
                            onTap: () => setState(
                                () => _genderFilter = _GenderFilter.female),
                          ),
                          _FilterChip(
                            label: 'Male',
                            selected: _genderFilter == _GenderFilter.male,
                            onTap: () => setState(
                                () => _genderFilter = _GenderFilter.male),
                          ),
                          const SizedBox(width: 4),
                          _FilterChip(
                            label: 'American',
                            selected: _accentFilter ==
                                VoiceLanguage.americanEnglish,
                            onTap: () => setState(() {
                              _accentFilter =
                                  _accentFilter == VoiceLanguage.americanEnglish
                                      ? null
                                      : VoiceLanguage.americanEnglish;
                            }),
                          ),
                          _FilterChip(
                            label: 'British',
                            selected:
                                _accentFilter == VoiceLanguage.britishEnglish,
                            onTap: () => setState(() {
                              _accentFilter =
                                  _accentFilter == VoiceLanguage.britishEnglish
                                      ? null
                                      : VoiceLanguage.britishEnglish;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap ▶ to hear: "${KokoroVoices.previewSentence}"',
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty && favorites.isEmpty && recents.isEmpty
                    ? const Center(child: Text('No voices match'))
                    : ListView(
                        controller: scrollController,
                        children: [
                          if (favorites.isNotEmpty) ...[
                            _SectionHeader('FAVORITES'),
                            ReorderableListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              onReorder: (oldIndex, newIndex) => ref
                                  .read(favoriteVoiceIdsProvider.notifier)
                                  .reorder(oldIndex, newIndex),
                              children: [
                                for (final v in favorites)
                                  _VoiceRow(
                                    key: ValueKey('fav_${v.id}'),
                                    voice: v,
                                    isCurrent: v.id == widget.currentVoiceId,
                                    isFavorite: true,
                                    isPlaying: _playingVoiceId == v.id,
                                    isLoadingSample: _loadingVoiceId == v.id,
                                    onTap: () => _select(v),
                                    onToggleFavorite: () => ref
                                        .read(favoriteVoiceIdsProvider.notifier)
                                        .toggle(v.id),
                                    onToggleSample: () => _toggleSample(v),
                                    dragHandle: true,
                                  ),
                              ],
                            ),
                          ],
                          if (recents.isNotEmpty) ...[
                            _SectionHeader('RECENTLY USED'),
                            for (final v in recents)
                              _VoiceRow(
                                voice: v,
                                isCurrent: v.id == widget.currentVoiceId,
                                isFavorite: false,
                                isPlaying: _playingVoiceId == v.id,
                                isLoadingSample: _loadingVoiceId == v.id,
                                onTap: () => _select(v),
                                onToggleFavorite: () => ref
                                    .read(favoriteVoiceIdsProvider.notifier)
                                    .toggle(v.id),
                                onToggleSample: () => _toggleSample(v),
                              ),
                          ],
                          for (final isFemale in const [true, false])
                            if ((byGender[isFemale] ?? const []).isNotEmpty) ...[
                              _SectionHeader(isFemale ? 'FEMALE' : 'MALE'),
                              for (final v in byGender[isFemale]!)
                                _VoiceRow(
                                  voice: v,
                                  isCurrent: v.id == widget.currentVoiceId,
                                  isFavorite: favoriteIds.contains(v.id),
                                  isPlaying: _playingVoiceId == v.id,
                                  isLoadingSample: _loadingVoiceId == v.id,
                                  onTap: () => _select(v),
                                  onToggleFavorite: () => ref
                                      .read(favoriteVoiceIdsProvider.notifier)
                                      .toggle(v.id),
                                  onToggleSample: () => _toggleSample(v),
                                ),
                            ],
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    super.key,
    required this.voice,
    required this.isCurrent,
    required this.isFavorite,
    required this.isPlaying,
    required this.isLoadingSample,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onToggleSample,
    this.dragHandle = false,
  });

  final KokoroVoice voice;
  final bool isCurrent;
  final bool isFavorite;
  final bool isPlaying;
  final bool isLoadingSample;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleSample;
  final bool dragHandle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        voice.isFemale ? Icons.woman : Icons.man,
        color: AppColors.textMuted,
      ),
      title: Text(voice.name),
      subtitle: Text(voice.language.label),
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
          else if (dragHandle)
            const Icon(Icons.drag_handle, color: AppColors.textMuted)
          else
            const SizedBox(width: 24),
        ],
      ),
    );
  }
}
