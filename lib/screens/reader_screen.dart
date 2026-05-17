import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/chapter.dart';
import '../models/downloaded_chapter.dart';
import '../models/novel.dart';
import '../providers/audio_providers.dart';
import '../providers/download_providers.dart';
import '../providers/playback_coordinator.dart';
import '../providers/progress_providers.dart';
import '../router.dart';
import '../services/chapter_api.dart';
import '../services/offline_content_service.dart';
import '../theme/app_theme.dart';
import '../widgets/global_mini_player.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.novel,
    required this.chapter,
    this.startParagraph,
    this.chapters = const [],
  });
  final Novel novel;
  final Chapter chapter;
  final int? startParagraph;
  final List<Chapter> chapters;

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
  List<Chapter> _localChapters = [];

  /// Chapter content for *this* screen only — independent of whatever the
  /// audio handler is currently playing. Decoupling the displayed content
  /// from `audioStateProvider.content` is what fixes the cross-chapter
  /// highlight bug: when the user navigates between chapters while a
  /// different chapter is still playing, this screen always shows the
  /// chapter it was opened with, never the playing chapter's text.
  List<String> _displayContent = const [];
  bool _contentLoading = true;
  Object? _contentError;

  @override
  void initState() {
    super.initState();
    _localChapters = List.of(widget.chapters);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    // Clear keys eagerly so any stale GlobalKey references can't be
    // resurrected by a late frame callback after navigation.
    _itemKeys.clear();
    _scroll.dispose();
    super.dispose();
  }

  String get _titleLine =>
      'Chapter ${widget.chapter.chapterNumber}: ${widget.chapter.chapterTitle}';

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    // Load chapter list in the background so prev/next buttons activate even
    // when the reader is opened from the mini player or downloads screen.
    if (_localChapters.isEmpty) unawaited(_loadChapterList());

    await _loadDisplayContent();

    // Once content is loaded, optionally auto-scroll to the start paragraph.
    final start = widget.startParagraph;
    if (start != null && mounted) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) await _scrollToActive(start);
    }
  }

  Future<void> _loadDisplayContent() async {
    try {
      // Offline-first lookup, falling back to the network. This is the same
      // logic the coordinator uses, kept local so the reader can render
      // without mutating audio state.
      final offline = await offlineContentService.getOfflineChapterContent(
        widget.novel.slug,
        widget.chapter.chapterNumber,
      );
      List<String> raw;
      if (offline != null) {
        raw = offline.content;
      } else {
        final remote = await chapterApi.getChapterContent(
          chapterNumber: widget.chapter.chapterNumber,
          novelSlug: widget.novel.slug,
        );
        raw = remote.content;
      }
      if (!mounted) return;
      setState(() {
        _displayContent = [_titleLine, ...raw];
        _contentLoading = false;
        _contentError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contentLoading = false;
        _contentError = e;
      });
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
        if (!_scroll.hasClients) return;
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
      if (_autoScrolling && _scroll.hasClients) _scroll.jumpTo(_scroll.offset);
      _autoScrolling = false;
      if (_followMode) setState(() => _followMode = false);
    }
    return false;
  }

  /// True when the audio state's currently-loaded chapter matches the
  /// chapter this screen is displaying. Highlights, follow-mode scrolling,
  /// and the "now playing" indicator all gate on this so audio belonging
  /// to a different chapter never paints onto this screen.
  bool _isPlayingThisChapter(AudioState state) {
    return state.novel?.slug == widget.novel.slug &&
        state.chapter?.chapterNumber == widget.chapter.chapterNumber;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioStateProvider);
    final isThisChapter = _isPlayingThisChapter(state);

    // Follow mode: auto-scroll to active paragraph whenever it changes,
    // but only while (a) the user has opted in via the AppBar button AND
    // (b) the audio state's chapter matches this screen — otherwise an
    // auto-advance in a different chapter would scroll our paragraphs.
    ref.listen<AudioState>(audioStateProvider, (prev, next) {
      if (!_followMode) return;
      if (!_isPlayingThisChapter(next)) return;
      if (prev?.currentIndex == next.currentIndex) return;
      final idx = next.currentIndex;
      if (idx == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActive(idx);
      });
    });

    final hasPlaying = isThisChapter && state.currentIndex != null;

    final downloads = ref.watch(downloadsProvider);
    final downloadRecord = _findDownload(downloads.items);
    final downloaded = downloadRecord?.status == DownloadStatusValue.completed;
    final downloading = downloadRecord?.status == DownloadStatusValue.pending ||
        downloadRecord?.status == DownloadStatusValue.processing ||
        downloads.active.containsKey(downloadRecord?.downloadId);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Ch ${widget.chapter.chapterNumber}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          _ChapterNavButton(
            icon: Icons.chevron_left,
            tooltip: 'Previous chapter',
            chapter: _adjacentChapter(-1),
            novel: widget.novel,
            allChapters: _localChapters,
            context: context,
          ),
          _ChapterNavButton(
            icon: Icons.chevron_right,
            tooltip: 'Next chapter',
            chapter: _adjacentChapter(1),
            novel: widget.novel,
            allChapters: _localChapters,
            context: context,
          ),
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
                  setState(() => _followMode = false);
                } else {
                  setState(() => _followMode = true);
                  _scrollToActive(idx);
                }
              },
            ),
          IconButton(
            tooltip: downloaded
                ? 'Downloaded for offline playback'
                : (downloading ? 'Downloading\u2026' : 'Download for offline'),
            icon: Icon(
              downloaded
                  ? Icons.check_circle
                  : (downloading ? Icons.downloading : Icons.download),
              color: downloaded
                  ? AppColors.success
                  : (downloading ? AppColors.accent : null),
            ),
            onPressed: downloaded || downloading ? null : _startDownload,
          ),
          IconButton(
            onPressed: () => _showSettings(context),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(state, isThisChapter),
          const Align(
            alignment: Alignment.bottomCenter,
            child: GlobalMiniPlayer(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AudioState state, bool isThisChapter) {
    if (_contentLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_contentError != null && _displayContent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.accent, size: 32),
              const SizedBox(height: 12),
              Text(
                'Could not load chapter:\n$_contentError',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _contentLoading = true;
                    _contentError = null;
                  });
                  _loadDisplayContent();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return NotificationListener<ScrollStartNotification>(
      onNotification: _onUserScroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        itemCount: _displayContent.length,
        itemBuilder: (_, index) {
          final key = _itemKeys.putIfAbsent(index, () => GlobalKey());
          // Highlight ONLY when the audio state belongs to this chapter
          // AND the active index matches. This is the core fix for the
          // stale-highlight-across-chapters bug.
          final isActive =
              isThisChapter && state.currentIndex == index;
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
              onTap: () => _onParagraphTap(index),
              child: Text(
                _displayContent[index],
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
    );
  }

  Future<void> _onParagraphTap(int index) async {
    // Strip the prepended title line (index 0) before passing the
    // paragraph list to the coordinator — the coordinator re-adds the
    // title in `loadChapter`, matching the offline-audio off-by-one
    // mapping (paragraph 0 → title.mp3).
    final paragraphs = _displayContent.length > 1
        ? _displayContent.sublist(1)
        : <String>[];
    await ref.read(playbackCoordinatorProvider).playChapterParagraph(
          novel: widget.novel,
          chapter: widget.chapter,
          paragraphIndex: index,
          content: paragraphs,
        );
    // Refresh server progress so the chapter list / novel list reflect
    // the latest cross-device state shortly after we kick off playback.
    if (mounted) {
      ref.read(progressProvider.notifier).refresh();
    }
  }

  Future<void> _loadChapterList() async {
    try {
      final first = await chapterApi.getChaptersList(widget.novel.slug);
      var all = List<Chapter>.of(first.chapters);
      if (first.totalPages > 1) {
        final rest = await Future.wait([
          for (var p = 2; p <= first.totalPages; p++)
            chapterApi.getChaptersList(widget.novel.slug, page: p),
        ]);
        for (final r in rest) {
          all.addAll(r.chapters);
        }
        all.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
      }
      if (mounted) setState(() => _localChapters = all);
    } catch (_) {}
  }

  Chapter? _adjacentChapter(int delta) {
    if (_localChapters.isEmpty) return null;
    final idx = _localChapters.indexWhere(
      (c) => c.chapterNumber == widget.chapter.chapterNumber,
    );
    if (idx == -1) return null;
    final target = idx + delta;
    if (target < 0 || target >= _localChapters.length) return null;
    return _localChapters[target];
  }

  DownloadedChapter? _findDownload(List<DownloadedChapter> list) {
    try {
      return list.firstWhere(
        (d) =>
            d.novelName == widget.novel.slug &&
            d.chapterNumber == widget.chapter.chapterNumber,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _startDownload() async {
    final narrator = ref.read(narratorVoiceProvider);
    final dialogue = ref.read(dialogueVoiceProvider);
    await ref.read(downloadsProvider.notifier).startDownload(
          DownloadRequest(
            novelName: widget.novel.slug,
            chapterNumber: widget.chapter.chapterNumber,
            narratorVoice: narrator,
            dialogueVoice: dialogue,
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

class _ChapterNavButton extends StatelessWidget {
  const _ChapterNavButton({
    required this.icon,
    required this.tooltip,
    required this.chapter,
    required this.novel,
    required this.allChapters,
    required this.context,
  });

  final IconData icon;
  final String tooltip;
  final Chapter? chapter;
  final Novel novel;
  final List<Chapter> allChapters;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    return IconButton(
      tooltip: chapter != null ? '$tooltip: Ch ${chapter!.chapterNumber}' : tooltip,
      icon: Icon(icon, color: chapter != null ? null : Colors.white24),
      onPressed: chapter == null
          ? null
          : () => context.pushReplacement(
                '/reader',
                extra: ReaderArgs(
                  novel: novel,
                  chapter: chapter!,
                  chapters: allChapters,
                ),
              ),
    );
  }
}
