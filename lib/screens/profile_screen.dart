import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_providers.dart';
import '../providers/backend_provider.dart';
import '../providers/progress_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/backend_picker.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user ?? '—';
    final progress = ref.watch(progressProvider);
    final backend = ref.watch(backendProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CircleAvatar(
            radius: 40,
            child: Icon(Icons.person, size: 40),
          ),
          const SizedBox(height: 12),
          Text(
            user,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Reading Progress',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (progress.isEmpty)
            const Text('No progress yet. Start reading!')
          else
            ...progress.entries.map((e) => Card(
                  child: ListTile(
                    title: Text(e.key),
                    subtitle: Text('Last read: Chapter ${e.value}'),
                  ),
                )),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => showBackendPicker(context),
            icon: const Icon(Icons.dns),
            label: Text('Backend: ${backend.label}'),
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
