import 'package:flutter/material.dart';

import '../../providers/last_position_provider.dart';
import '../../theme/app_theme.dart';

/// Card surfaced at the top of the chapter list when the user has a
/// last-known reading position for this novel — either from the server's
/// progress API ([chapterNumber] only) or from the richer client-side
/// last-position tracker ([position] with paragraph + preview text).
class ContinueReadingCard extends StatelessWidget {
  const ContinueReadingCard({
    super.key,
    this.position,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.onTap,
  });

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
              const Row(
                children: [
                  Icon(Icons.bookmark, color: AppColors.primary, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'CONTINUE READING',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: AppColors.primary,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.play_circle,
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
