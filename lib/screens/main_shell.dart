import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/global_mini_player.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  int _indexFromRoute(String location) {
    if (location.startsWith('/downloads')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexFromRoute(location);
    return Scaffold(
      body: Stack(
        children: [
          child,
          const Align(
            alignment: Alignment.bottomCenter,
            child: GlobalMiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Novels',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/novels');
              break;
            case 1:
              context.go('/downloads');
              break;
            case 2:
              context.go('/profile');
              break;
          }
        },
      ),
    );
  }
}
