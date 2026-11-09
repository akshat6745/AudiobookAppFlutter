import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/novel.dart';
import '../providers/auth_providers.dart';
import '../providers/progress_providers.dart';
import '../services/novel_api.dart';
import '../theme/app_theme.dart';

final _novelsFutureProvider = FutureProvider.autoDispose<List<Novel>>((ref) {
  // Still watches auth so the list refetches on sign-in/out; the backend
  // scopes the library to the access token, not to a username we send.
  ref.watch(authProvider).user;
  return novelApi.getAllNovels();
});

class NovelListScreen extends ConsumerStatefulWidget {
  const NovelListScreen({super.key});

  @override
  ConsumerState<NovelListScreen> createState() => _NovelListScreenState();
}

class _NovelListScreenState extends ConsumerState<NovelListScreen> {
  String _query = '';
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Refresh server-side progress when this tab becomes visible so the
    // "Ch. N" last-read badge reflects cross-device state. The provider
    // throttles, so frequent tab switches won't spam the backend.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(progressProvider.notifier).refresh();
    });
  }

  Future<void> _handleUploadEbook() async {
    if (_isUploading) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not open the file picker.');
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final path = picked.path;
    if (path == null || !picked.name.toLowerCase().endsWith('.epub')) {
      _showMessage('Please select an EPUB (.epub) file.');
      return;
    }

    setState(() => _isUploading = true);
    try {
      final response = await novelApi.uploadEpub(
        filePath: path,
        fileName: picked.name,
      );
      if (!mounted) return;
      _showMessage(response.message.isNotEmpty
          ? response.message
          : '"${response.title}" was added to your library.');
      ref.invalidate(_novelsFutureProvider);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? (e.response?.data as Map)['detail'] as String?
          : null;
      _showMessage(detail ?? 'Could not upload the ebook. Please try again.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not upload the ebook. Please try again.');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _confirmAndDeleteNovel(Novel novel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Novel?'),
        content: Text(
          'Delete "${novel.title}" from your library? This only deletes the copy you uploaded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final ok = await novelApi.deleteNovel(novel.slug);
      if (!mounted) return;
      if (ok) {
        _showMessage('Deleted "${novel.title}".');
        ref.invalidate(_novelsFutureProvider);
        ref.read(progressProvider.notifier).refresh(force: true);
      } else {
        _showMessage('Could not delete "${novel.title}".');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? (e.response?.data as Map)['detail'] as String?
          : null;
      _showMessage(detail ?? 'Could not delete "${novel.title}".');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not delete "${novel.title}".');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_novelsFutureProvider);
    final progress = ref.watch(progressProvider);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi, ${ref.watch(authProvider).user ?? "reader"}!',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Your Library',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search novels...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _handleUploadEbook,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(_isUploading ? 'Uploading...' : 'Upload Ebook'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load novels:\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (novels) {
                final filtered = _query.isEmpty
                    ? novels
                    : novels.where((n) {
                        final t = n.title.toLowerCase();
                        final a = (n.author ?? '').toLowerCase();
                        return t.contains(_query) || a.contains(_query);
                      }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No novels found'));
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    // Pull-to-refresh on the novel list also forces a
                    // progress refresh so badges update immediately.
                    await Future.wait([
                      ref.refresh(_novelsFutureProvider.future),
                      ref
                          .read(progressProvider.notifier)
                          .refresh(force: true),
                    ]);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final n = filtered[i];
                      final lastChapter = progress[n.slug];
                      return _NovelCard(
                        novel: n,
                        lastChapter: lastChapter,
                        onDelete: n.isOwner ? () => _confirmAndDeleteNovel(n) : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NovelCard extends StatelessWidget {
  const _NovelCard({
    required this.novel,
    required this.lastChapter,
    this.onDelete,
  });
  final Novel novel;
  final int? lastChapter;
  final VoidCallback? onDelete;

  // Displayed at 70x100 logical pixels — cap the decoded bitmap to that size
  // (times device pixel ratio) instead of whatever resolution the backend
  // serves. Covers are frequently much larger than a 70x100 thumbnail, and
  // without this every decoded image sits in the image cache at full
  // resolution, multiplied by however many novels are in the (unbounded)
  // ListView.builder scroll history.
  static const _coverWidth = 70.0;
  static const _coverHeight = 100.0;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => context.push('/chapters', extra: novel),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: novelApi.coverUrl(novel.slug),
                  width: _coverWidth,
                  height: _coverHeight,
                  fit: BoxFit.cover,
                  memCacheWidth: (_coverWidth * dpr).round(),
                  memCacheHeight: (_coverHeight * dpr).round(),
                  errorWidget: (_, __, ___) => Container(
                    width: _coverWidth,
                    height: _coverHeight,
                    color: AppColors.surfaceDark,
                    child: const Icon(Icons.book, color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      novel.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (novel.author != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        novel.author!,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.menu_book,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          '${novel.chapterCount ?? "?"} chapters',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                        ),
                        if (lastChapter != null) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Ch. $lastChapter',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                  tooltip: 'Delete novel',
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
