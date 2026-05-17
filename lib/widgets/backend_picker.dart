import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/backend_provider.dart';
import '../router.dart';
import '../services/api_client.dart';

/// Show a modal bottom sheet that lets the user pick which backend the
/// app talks to. Reachable from anywhere via the floating overlay added
/// in `MaterialApp.builder`.
Future<void> showBackendPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _BackendPickerSheet(),
  );
}

class _BackendPickerSheet extends ConsumerWidget {
  const _BackendPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(backendProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backend',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...BackendChoice.values.map(
              (b) => RadioListTile<BackendChoice>(
                value: b,
                groupValue: selected,
                onChanged: (choice) async {
                  if (choice == null) return;
                  await ref.read(backendProvider.notifier).select(choice);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Switched to ${choice.label}')),
                    );
                  }
                },
                title: Text(b.label),
                subtitle: Text(
                  b.url,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small floating affordance pinned by `MaterialApp.builder`'s overlay
/// stack so the backend picker is reachable from every screen without
/// crowding the AppBar action zone.
class BackendPickerOverlayButton extends StatelessWidget {
  const BackendPickerOverlayButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          // Use the router's navigator context — this widget lives above
          // the router in MaterialApp.builder, so its own context has no
          // Navigator ancestor.
          final navContext = rootNavigatorKey.currentContext;
          if (navContext != null) showBackendPicker(navContext);
        },
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.dns, size: 16, color: Colors.white70),
        ),
      ),
    );
  }
}
