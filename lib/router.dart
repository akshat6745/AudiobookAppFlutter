import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/chapter.dart';
import 'models/novel.dart';
import 'providers/auth_providers.dart';
import 'screens/chapter_list_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/novel_list_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/register_screen.dart';

GoRouter appRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/novels',
    redirect: (context, state) {
      final user = ref.read(authProvider).user;
      final isAuth = user != null;
      final goingAuth = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      if (!isAuth && !goingAuth) return '/login';
      if (isAuth && goingAuth) return '/novels';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/novels',
            builder: (_, __) => const NovelListScreen(),
          ),
          GoRoute(
            path: '/downloads',
            builder: (_, __) => const DownloadsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/chapters',
        builder: (context, state) {
          final novel = state.extra as Novel;
          return ChapterListScreen(novel: novel);
        },
      ),
      GoRoute(
        path: '/reader',
        builder: (context, state) {
          final args = state.extra as ReaderArgs;
          return ReaderScreen(
            novel: args.novel,
            chapter: args.chapter,
            startParagraph: args.startParagraph,
          );
        },
      ),
    ],
  );
}

class ReaderArgs {
  final Novel novel;
  final Chapter chapter;
  final int? startParagraph;
  const ReaderArgs({
    required this.novel,
    required this.chapter,
    this.startParagraph,
  });
}
