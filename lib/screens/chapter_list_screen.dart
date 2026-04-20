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
  final List<Chapter> _chapters = [];
  int _page = 1;
  int _totalPages = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || _page > _totalPages) return;
    setState(() => _isLoading = true);
    try {
      final resp = await chapterApi.getChaptersList(
        widget.novel.slug,
        page: _page,
      );
      setState(() {
        _chapters.addAll(resp.chapters);
        _totalPages = resp.totalPages;
        _page++;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastChapter = ref.watch(progressProvider)[widget.novel.slug];
    final downloads = ref.watch(downloadsProvider);
    final lastPosition = ref.watch(lastPositionProvider)[widget.novel.slug];

    // Show a "Continue Reading" card when we know the last-read chapter —
    // either from the server progress API or from the richer client-side
    // position tracker (which also has paragraph info).
    final hasLastRead = lastPosition != null || lastChapter != null;
    final totalCount = _chapters.length + (hasLastRead ? 1 : 0) + 1;

    return Scaffold(
      appBar: AppBar(title: Text(widget.novel.title)),
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                _loadMore();
              }
              return false;
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 120),
              itemCount: totalCount,
              itemBuilder: (_, i) {
                if (hasLastRead && i == 0) {
                  // Prefer client-side position (has paragraph), fall back
                  // to server progress API (chapter only).
                  final chNum = lastPosition?.chapter ?? lastChapter!;
                  final chapter = _chapters.isEmpty
                      ? Chapter(
                          chapterNumber: chNum,
                          chapterTitle: 'Chapter $chNum',
                        )
                      : _chapters.firstWhere(
                          (c) => c.chapterNumber == chNum,
                          orElse: () => Chapter(
                            chapterNumber: chNum,
                            chapterTitle: 'Chapter $chNum',
                          ),
                        );
                  return _ContinueReadingCard(
                    novel: widget.novel,
                    position: lastPosition,
                    chapterNumber: chNum,
                    chapterTitle: chapter.chapterTitle,
                    onTap: () {
                      context.push(
                        '/reader',
                        extra: ReaderArgs(
                          novel: widget.novel,
                          chapter: chapter,
                          startParagraph: lastPosition?.paragraph,
                        ),
                      );
                    },
                  );
                }
                final chapterIndex = i - (hasLastRead ? 1 : 0);
                if (chapterIndex >= _chapters.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : const SizedBox.shrink(),
                  );
                }
                final ch = _chapters[chapterIndex];
                final isLastRead = lastChapter == ch.chapterNumber;
                final downloadRecord = _findDownload(downloads.items, ch);
                return _ChapterTile(
                  novel: widget.novel,
                  chapter: ch,
                  isLastRead: isLastRead,
                  download: downloadRecord,
                  onPlay: () {
                    final args = ReaderArgs(novel: widget.novel, chapter: ch);
                    context.push('/reader', extra: args);
                  },
                  onDownload: () async {
                    final narrator = ref.read(narratorVoiceProvider);
                    final dialogue = ref.read(dialogueVoiceProvider);
                    await ref
                        .read(downloadsProvider.notifier)
                        .startDownload(
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
                    ? 'Chapter $chapterNumber · Paragraph ${position!.paragraph}'
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
