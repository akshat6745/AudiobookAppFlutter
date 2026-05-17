import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Bottom bar with prev / next page buttons and a tappable page indicator
/// that opens a "Go to page" dialog. Used by the chapter list screen.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
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
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
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
