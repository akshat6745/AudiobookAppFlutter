import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/novel.dart';
import '../providers/auth_providers.dart';
import '../providers/progress_providers.dart';
import '../services/novel_api.dart';
import '../theme/app_theme.dart';

final _novelsFutureProvider = FutureProvider.autoDispose<List<Novel>>((ref) {
  final user = ref.watch(authProvider).user;
  return novelApi.getAllNovels(username: user);
});

class NovelListScreen extends ConsumerStatefulWidget {
  const NovelListScreen({super.key});

  @override
  ConsumerState<NovelListScreen> createState() => _NovelListScreenState();
}

class _NovelListScreenState extends ConsumerState<NovelListScreen> {
  String _query = '';

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
                  onRefresh: () =>
                      ref.refresh(_novelsFutureProvider.future),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final n = filtered[i];
                      final lastChapter = progress[n.slug];
                      return _NovelCard(novel: n, lastChapter: lastChapter);
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
  const _NovelCard({required this.novel, required this.lastChapter});
  final Novel novel;
  final int? lastChapter;

  @override
  Widget build(BuildContext context) {
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
                  width: 70,
                  height: 100,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 70,
                    height: 100,
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
            ],
          ),
        ),
      ),
    );
  }
}
