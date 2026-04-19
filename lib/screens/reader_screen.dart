import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chapter.dart';
import '../models/novel.dart';
import '../providers/audio_providers.dart';
import '../providers/playback_coordinator.dart';
import '../theme/app_theme.dart';
import '../widgets/global_mini_player.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.novel,
    required this.chapter,
    this.startParagraph,
  });
  final Novel novel;
  final Chapter chapter;
  final int? startParagraph;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _scroll = ScrollController();
  final _itemKeys = <int, GlobalKey>{};
  double _fontSize = 16;
  bool _initialized = false;
  bool _autoScrolling = false;
  bool _followMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    final coord = ref.read(playbackCoordinatorProvider);
    await coord.loadChapter(
      novel: widget.novel,
      chapter: widget.chapter,
    );
    final start = widget.startParagraph;
    if (start != null && mounted) {
      // Let the ListView build at least once before we try to locate the target.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) await _scrollToActive(start);
    }
  }

  Future<void> _scrollToActive(int index) async {
    if (!_scroll.hasClients) return;
    _autoScrolling = true;
    try {
      // Retry up to 3 passes: if the target isn't built yet, jump to an
      // estimated offset based on the current average item height, wait a
      // frame, recompute (now with more measurements), and try again.
      for (var attempt = 0; attempt < 3; attempt++) {
        final ctx = _itemKeys[index]?.currentContext;
        if (ctx != null) {
          // ignore: use_build_context_synchronously
          await Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 300), alignment: 0.5);
          return;
        }
        final position = _scroll.position;
        final viewport = position.viewportDimension;
        final avgH = _averageItemHeight();
        final estOffset =
            (avgH * index - viewport / 2 + avgH / 2)
                .clamp(0.0, position.maxScrollExtent);
        _scroll.jumpTo(estOffset);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
    } finally {
      _autoScrolling = false;
    }
  }

  double _averageItemHeight() {
    var total = 0.0, count = 0;
    for (final k in _itemKeys.values) {
      final box = k.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.size.height > 0) {
        total += box.size.height;
        count++;
      }
    }
    return count == 0 ? 100.0 : total / count;
  }

  bool _onUserScroll(ScrollStartNotification n) {
    // Real user drag → exit follow mode and interrupt any auto-scroll.
    if (n.dragDetails != null) {
      if (_autoScrolling) _scroll.jumpTo(_scroll.offset);
      _autoScrolling = false;
      if (_followMode) setState(() => _followMode = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioStateProvider);
    final content = state.content;

    // Follow mode: auto-scroll to active paragraph whenever it changes, but
    // only while the user has opted in via the AppBar button.
    ref.listen(audioStateProvider, (prev, next) {
      if (!_followMode) return;
      if (prev?.currentIndex == next.currentIndex) return;
      final idx = next.currentIndex;
      if (idx == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive(idx));
    });

    final hasPlaying = state.currentIndex != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Ch ${widget.chapter.chapterNumber}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (hasPlaying)
            IconButton(
              tooltip: _followMode
                  ? 'Following playback (tap to stop)'
                  : 'Scroll to playing paragraph and follow',
              icon: Icon(
                _followMode ? Icons.my_location : Icons.location_searching,
                color: _followMode ? AppColors.primary : null,
              ),
              onPressed: () {
                final idx = state.currentIndex;
                if (idx == null) return;
                if (_followMode) {
                  // Second tap exits follow mode (no scroll).
                  setState(() => _followMode = false);
                } else {
                  setState(() => _followMode = true);
                  _scrollToActive(idx);
                }
              },
            ),
          IconButton(
            onPressed: () => _showSettings(context),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Stack(
        children: [
          content.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : NotificationListener<ScrollStartNotification>(
              onNotification: _onUserScroll,
              child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              itemCount: content.length,
              itemBuilder: (_, index) {
                final key = _itemKeys.putIfAbsent(index, () => GlobalKey());
                final isActive = state.currentIndex == index;
                final isTitle = index == 0;
                return Container(
                  key: key,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary.withOpacity(0.12)
                        : AppColors.cardDark,
                    borderRadius: BorderRadius.circular(8),
                    border: isActive
                        ? const Border(
                            left: BorderSide(
                                color: AppColors.primary, width: 3),
                          )
                        : null,
                  ),
                  child: InkWell(
                    onTap: () {
                      ref
                          .read(playbackCoordinatorProvider)
                          .playParagraph(index);
                    },
                    child: Text(
                      content[index],
                      style: TextStyle(
                        fontSize: isTitle ? _fontSize + 6 : _fontSize,
                        fontWeight:
                            isTitle ? FontWeight.bold : FontWeight.normal,
                        height: 1.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: GlobalMiniPlayer(),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Reader Settings',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Font size'),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          if (_fontSize > 12) {
                            setState(() => _fontSize--);
                            setModal(() {});
                          }
                        },
                      ),
                      Text('${_fontSize.toInt()}'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          if (_fontSize < 24) {
                            setState(() => _fontSize++);
                            setModal(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              const Text('Playback speed'),
              StreamBuilder<PlaybackState>(
                stream: handler.playbackState,
                builder: (_, snap) {
                  final current = snap.data?.speed ?? 1.0;
                  return Wrap(
                    spacing: 8,
                    children: [
                      for (final s in const [
                        0.75,
                        1.0,
                        1.25,
                        1.5,
                        1.75,
                        2.0
                      ])
                        ChoiceChip(
                          label: Text('${s}x'),
                          selected: (current - s).abs() < 0.01,
                          onSelected: (_) async {
                            await ref
                                .read(playbackCoordinatorProvider)
                                .setSpeed(s);
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
