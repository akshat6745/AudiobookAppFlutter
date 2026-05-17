import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/chapter.dart';
import '../models/downloaded_chapter.dart';
import '../models/novel.dart';
import '../providers/audio_providers.dart';
import '../providers/download_providers.dart';
import '../providers/last_position_provider.dart';
import '../providers/progress_providers.dart';
import '../router.dart';
import '../services/chapter_api.dart';
import '../widgets/chapter_list/chapter_list_body.dart';
import '../widgets/chapter_list/continue_reading_card.dart';
import '../widgets/chapter_list/jump_to_page_dialog.dart';
import '../widgets/chapter_list/pagination_bar.dart';
import '../widgets/global_mini_player.dart';

/// Paginated list of chapters for a novel. Hosts a "Continue Reading"
/// card, the chapter list, and a [PaginationBar]; delegates rendering
/// of each section to widgets in `lib/widgets/chapter_list/`.
class ChapterListScreen extends ConsumerStatefulWidget {
  const ChapterListScreen({super.key, required this.novel});
  final Novel novel;

  @override
  ConsumerState<ChapterListScreen> createState() =>
      _ChapterListScreenState();
}

class _ChapterListScreenState extends ConsumerState<ChapterListScreen> {
  /// Cached pages — `Map<page number, chapters on that page>`. Keeping
  /// this in memory means flipping back to a previously-viewed page is
  /// instant and we don't lose what we've already paid network cost for.
  final Map<int, List<Chapter>> _pageCache = {};

  /// Persists scroll offsets per-page so the user returns to where they
  /// were inside a page after going prev/next/jump and coming back.
  final Map<int, double> _scrollOffsetByPage = {};
  final ScrollController _scroll = ScrollController();

  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = false;
  Object? _error;

  /// Suppress the persistence listener during page transitions. Without
  /// this, the listener fires while the new page's ListView lays out
  /// (briefly reporting offset 0) and clobbers the saved offset before
  /// our restore frame callback runs.
  bool _suppressOffsetPersist = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_persistScrollOffset);
    _loadPage(1);
    // Refresh server-side progress when entering this screen so the
    // "last read" badge / Continue Reading card reflect cross-device state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(progressProvider.notifier).refreshNovel(widget.novel.slug);
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_persistScrollOffset);
    _scroll.dispose();
    super.dispose();
  }

  // ---- Pagination state ----

  void _persistScrollOffset() {
    if (_suppressOffsetPersist) return;
    if (!_scroll.hasClients) return;
    _scrollOffsetByPage[_currentPage] = _scroll.offset;
  }

  Future<void> _loadPage(int page) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final cached = _pageCache[page];
      ChapterListResponse? resp;
      if (cached == null) {
        resp = await chapterApi.getChaptersList(
          widget.novel.slug,
          page: page,
        );
        _pageCache[page] = resp.chapters;
      }

      if (!mounted) return;
      _suppressOffsetPersist = true;
      setState(() {
        _currentPage = page;
        if (resp != null) _totalPages = resp.totalPages;
        _isLoading = false;
      });

      // Restore the scroll offset we left this page at, after the new
      // ListView has had a chance to lay out its children.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (!mounted || !_scroll.hasClients) return;
          final saved = _scrollOffsetByPage[page] ?? 0.0;
          final clamped =
              saved.clamp(0.0, _scroll.position.maxScrollExtent);
          _scroll.jumpTo(clamped);
        } finally {
          _suppressOffsetPersist = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      _suppressOffsetPersist = false;
      setState(() {
        _isLoading = false;
        _error = e;
      });
    }
  }

  Future<void> _goToPage(int page) async {
    if (page < 1 || page > _totalPages) return;
    if (page == _currentPage) return;
    _persistScrollOffset();
    await _loadPage(page);
  }

  Future<void> _onJumpTapped() async {
    final result = await showJumpToPageDialog(
      context,
      currentPage: _currentPage,
      totalPages: _totalPages,
    );
    if (result != null) await _goToPage(result);
  }

  Future<void> _onRefreshTapped() async {
    await ref
        .read(progressProvider.notifier)
        .refreshNovel(widget.novel.slug, force: true);
    if (!mounted) return;
    // Drop the page cache so the chapter list itself re-fetches if the
    // backend has new chapters; preserve the current page index.
    setState(() {
      _pageCache.clear();
      _scrollOffsetByPage.clear();
    });
    await _loadPage(_currentPage);
  }

  // ---- Lookup helpers ----

  /// Aggregate every chapter we've fetched so far across all loaded
  /// pages. Passed to [ReaderScreen] so prev/next chapter buttons work
  /// even across page boundaries.
  List<Chapter> _allLoadedChapters() {
    final all = <Chapter>[
      for (final entry in _pageCache.entries) ...entry.value,
    ];
    all.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    return all;
  }

  Chapter? _findChapter(int number) {
    for (final list in _pageCache.values) {
      for (final c in list) {
        if (c.chapterNumber == number) return c;
      }
    }
    return null;
  }

  String _resolveChapterTitle(int number) =>
      _findChapter(number)?.chapterTitle ?? 'Chapter $number';

  DownloadedChapter? _findDownload(
    List<DownloadedChapter> list,
    Chapter ch,
  ) {
    try {
      return list.firstWhere(
        (d) =>
            d.novelName == widget.novel.slug &&
            d.chapterNumber == ch.chapterNumber,
      );
    } catch (_) {
      return null;
    }
  }

  // ---- Navigation ----

  void _openReader(Chapter chapter, {int? startParagraph}) {
    context.push(
      '/reader',
      extra: ReaderArgs(
        novel: widget.novel,
        chapter: chapter,
        startParagraph: startParagraph,
        chapters: List.unmodifiable(_allLoadedChapters()),
      ),
    );
  }

  Future<void> _startDownload(Chapter chapter) async {
    final narrator = ref.read(narratorVoiceProvider);
    final dialogue = ref.read(dialogueVoiceProvider);
    await ref.read(downloadsProvider.notifier).startDownload(
          DownloadRequest(
            novelName: widget.novel.slug,
            chapterNumber: chapter.chapterNumber,
            narratorVoice: narrator,
            dialogueVoice: dialogue,
          ),
        );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(progressProvider);
    final lastChapter = progress[widget.novel.slug];
    final downloads = ref.watch(downloadsProvider);
    final lastPosition = ref.watch(lastPositionProvider)[widget.novel.slug];

    final chapters = _pageCache[_currentPage] ?? const <Chapter>[];
    final hasLastRead = lastPosition != null || lastChapter != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.novel.title),
        actions: [
          IconButton(
            tooltip: 'Refresh progress',
            icon: const Icon(Icons.refresh),
            onPressed: _onRefreshTapped,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (hasLastRead)
                ContinueReadingCard(
                  position: lastPosition,
                  chapterNumber: lastPosition?.chapter ?? lastChapter!,
                  chapterTitle: _resolveChapterTitle(
                    lastPosition?.chapter ?? lastChapter!,
                  ),
                  onTap: () {
                    final chNum = lastPosition?.chapter ?? lastChapter!;
                    final chapter = _findChapter(chNum) ??
                        Chapter(
                          chapterNumber: chNum,
                          chapterTitle: 'Chapter $chNum',
                        );
                    _openReader(chapter,
                        startParagraph: lastPosition?.paragraph);
                  },
                ),
              Expanded(
                child: ChapterListBody(
                  chapters: chapters,
                  isLoading: _isLoading,
                  error: _error,
                  lastChapter: lastChapter,
                  downloads: downloads.items,
                  scrollController: _scroll,
                  onRetry: () => _loadPage(_currentPage),
                  findDownload: (ch) => _findDownload(downloads.items, ch),
                  onPlay: (ch) => _openReader(ch),
                  onDownload: _startDownload,
                ),
              ),
              PaginationBar(
                currentPage: _currentPage,
                totalPages: _totalPages,
                isLoading: _isLoading,
                onPrev: _currentPage > 1
                    ? () => _goToPage(_currentPage - 1)
                    : null,
                onNext: _currentPage < _totalPages
                    ? () => _goToPage(_currentPage + 1)
                    : null,
                onJump: _totalPages > 1 ? _onJumpTapped : null,
              ),
            ],
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: GlobalMiniPlayer(),
          ),
        ],
      ),
    );
  }
}
