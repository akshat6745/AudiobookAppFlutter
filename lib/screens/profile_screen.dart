import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_providers.dart';
import '../providers/progress_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/tts_mode_selector.dart';
import '../widgets/tts_model_download_tile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user ?? '—';
    final progress = ref.watch(progressProvider);

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
          const _LinkGoogleButton(),
          const SizedBox(height: 24),
          Text(
            'Offline Playback',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          const TtsModeSelector(),
          const SizedBox(height: 12),
          const TtsModelDownloadTile(),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Logout'),
          ),
          const SizedBox(height: 12),
          const _DeleteAccountButton(),
        ],
      ),
    );
  }
}

class _DeleteAccountButton extends ConsumerStatefulWidget {
  const _DeleteAccountButton();

  @override
  ConsumerState<_DeleteAccountButton> createState() =>
      _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends ConsumerState<_DeleteAccountButton> {
  bool _deleting = false;

  Future<void> _confirmAndDelete() async {
    final user = ref.read(authProvider).user ?? 'your account';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text(
          'This will permanently delete "$user" and all of your saved reading progress. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final error = await ref.read(authProvider.notifier).deleteAccount();
    if (!mounted) return;
    setState(() => _deleting = false);

    if (error == null) {
      context.go('/login');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _deleting ? null : _confirmAndDelete,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: const BorderSide(color: AppColors.error),
      ),
      icon: _deleting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_forever_outlined),
      label: Text(_deleting ? 'Deleting account...' : 'Delete Account'),
    );
  }
}

/// Lets a password account add Google as a second way in.
class _LinkGoogleButton extends ConsumerStatefulWidget {
  const _LinkGoogleButton();

  @override
  ConsumerState<_LinkGoogleButton> createState() => _LinkGoogleButtonState();
}

class _LinkGoogleButtonState extends ConsumerState<_LinkGoogleButton> {
  bool _linking = false;

  Future<void> _link() async {
    setState(() => _linking = true);
    final result = await ref.read(authProvider.notifier).linkGoogle();
    if (!mounted) return;
    setState(() => _linking = false);
    if (result == null) return; // dismissed the Google sheet
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _linking ? null : _link,
      icon: _linking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.link),
      label: Text(_linking ? 'Linking...' : 'Link Google account'),
    );
  }
}
