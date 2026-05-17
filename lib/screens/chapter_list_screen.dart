import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../theme/app_theme.dart';
import '../widgets/global_mini_player.dart';

class ChapterListScreen extends ConsumerStatefulWidget {
  const ChapterListScreen({super.key, required this.novel});
  final Novel novel;

  @override
  ConsumerState<ChapterListScreen> createState() =>
      _ChapterListScreenState();
}

class _ChapterListScreenState extends ConsumerState<ChapterListScreen> {
  /// Cached pages — `Map<page number, chapters on that page>`. Keeping this
  /// in memory means flipping back to a previously-viewed page is instant
  /// and we don't lose what we've already paid network cost for.
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
        if (resp != null) {
          _totalPages = resp.totalPages;
        }
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

  Future<void> _showJumpToPageDialog() async {
    final controller =
        TextEditingController(text: _currentPage.toString());
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Page (1\u2013$_totalPages)',
              border: const OutlineInputBorder(),
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null) return 'Enter a page number';
              if (n < 1 || n > _totalPages) {
                return 'Out of range (1\u2013$_totalPages)';
              }
              return null;
            },
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(int.parse(controller.text));
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(int.parse(controller.text));
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) await _goToPage(result);
  }

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
            onPressed: () async {
              await ref
                  .read(progressProvider.notifier)
                  .refreshNovel(widget.novel.slug, force: true);
              // Also drop the page cache so the chapter list itself
              // refetches if the backend has new chapters.
              if (!mounted) return;
              setState(() {
                _pageCache.clear();
                _scrollOffsetByPage.clear();
              });
              await _loadPage(_currentPage);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (hasLastRead)
                _ContinueReadingCard(
                  novel: widget.novel,
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
                    final all = _allLoadedChapters();
                    context.push(
                      '/reader',
                      extra: ReaderArgs(
                        novel: widget.novel,
                        chapter: chapter,
                        startParagraph: lastPosition?.paragraph,
                        chapters: List.unmodifiable(all),
                      ),
                    );
                  },
                ),
              Expanded(
                child: _buildList(chapters, lastChapter, downloads.items),
              ),
              _PaginationBar(
                currentPage: _currentPage,
                totalPages: _totalPages,
                isLoading: _isLoading,
                onPrev: _currentPage > 1
                    ? () => _goToPage(_currentPage - 1)
                    : null,
                onNext: _currentPage < _totalPages
                    ? () => _goToPage(_currentPage + 1)
                    : null,
                onJump: _totalPages > 1 ? _showJumpToPageDialog : null,
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

  Widget _buildList(
    List<Chapter> chapters,
    int? lastChapter,
    List<DownloadedChapter> downloads,
  ) {
    if (_isLoading && chapters.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && chapters.isEmpty) {
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
                'Could not load chapters:\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _loadPage(_currentPage),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (chapters.isEmpty) {
      return const Center(child: Text('No chapters on this page.'));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: chapters.length,
      itemBuilder: (_, i) {
        final ch = chapters[i];
        final isLastRead = lastChapter == ch.chapterNumber;
        final downloadRecord = _findDownload(downloads, ch);
        return _ChapterTile(
          novel: widget.novel,
          chapter: ch,
          isLastRead: isLastRead,
          download: downloadRecord,
          onPlay: () {
            final all = _allLoadedChapters();
            context.push(
              '/reader',
              extra: ReaderArgs(
                novel: widget.novel,
                chapter: ch,
                chapters: List.unmodifiable(all),
              ),
            );
          },
          onDownload: () async {
            final narrator = ref.read(narratorVoiceProvider);
            final dialogue = ref.read(dialogueVoiceProvider);
            await ref.read(downloadsProvider.notifier).startDownload(
                  DownloadRequest(
                    novelName: widget.novel.slug,
                    chapterNumber: ch.chapterNumber,
                    narratorVoice: narrator,
                    dialogueVoice: dialogue,
                  ),
                );
          },
        );
      },
    );
  }

  /// Aggregate every chapter we've fetched so far across all loaded pages.
  /// We pass this to ReaderScreen so prev/next chapter buttons work even
  /// across page boundaries.
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

  String _resolveChapterTitle(int number) {
    final c = _findChapter(number);
    return c?.chapterTitle ?? 'Chapter $number';
  }

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
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.isLoading,
    required this.onPrev,
    required this.onNext,
    required this.onJump,
  });

  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        // Lift the bar above the persistent mini-player. The mini-player
        // also reserves SafeArea bottom inset so this offset matches.
        margin: const EdgeInsets.only(bottom: 80),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left),
              onPressed: isLoading ? null : onPrev,
            ),
            Expanded(
              child: GestureDetector(
                onTap: onJump,
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Page $currentPage of $totalPages',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (onJump != null)
                              const Icon(
                                Icons.edit,
                                size: 14,
                                color: AppColors.textMuted,
                              ),
                          ],
                        ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right),
              onPressed: isLoading ? null : onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({
    required this.novel,
    this.position,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.onTap,
  });

  final Novel novel;
  final LastPosition? position;
  final int chapterNumber;
  final String chapterTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      color: AppColors.surfaceDark,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bookmark, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'CONTINUE READING',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.play_circle,
                      color: AppColors.primary, size: 28),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                position != null
                    ? 'Chapter $chapterNumber \u00b7 Paragraph ${position!.paragraph}'
                    : 'Chapter $chapterNumber: $chapterTitle',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (position != null && position!.preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  position!.preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.novel,
    required this.chapter,
    required this.isLastRead,
    required this.download,
    required this.onPlay,
    required this.onDownload,
  });

  final Novel novel;
  final Chapter chapter;
  final bool isLastRead;
  final DownloadedChapter? download;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final downloaded = download?.status == DownloadStatusValue.completed;
    final downloading = download?.status == DownloadStatusValue.pending ||
        download?.status == DownloadStatusValue.processing;

    return Card(
      color: isLastRead
          ? AppColors.primary.withOpacity(0.12)
          : AppColors.cardDark,
      child: ListTile(
        title: Text(
          'Chapter ${chapter.chapterNumber}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chapter.chapterTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (isLastRead)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LAST READ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                downloaded
                    ? Icons.check_circle
                    : (downloading ? Icons.downloading : Icons.download),
                color: downloaded
                    ? AppColors.success
                    : (downloading ? AppColors.accent : Colors.white70),
              ),
              onPressed: downloaded || downloading ? null : onDownload,
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow, color: AppColors.primary),
              onPressed: onPlay,
            ),
          ],
        ),
        onTap: onPlay,
      ),
    );
  }
}
