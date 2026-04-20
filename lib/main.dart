import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/audio_providers.dart';
import 'providers/playback_coordinator.dart';
import 'router.dart';
import 'services/audio_cache_manager.dart';
import 'services/audio_handler.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Single AudioCacheManager instance shared by handler and providers so the
  // UI reads the same cache that's feeding the player.
  final cache = AudioCacheManager(
    narratorVoice: 'en-US-AvaMultilingualNeural',
    dialogueVoice: 'en-GB-RyanNeural',
  );

  final handler = await AudioService.init<AudiobookHandler>(
    builder: () => AudiobookHandler(cache: cache),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.audiobook.audiobook_app.audio',
      androidNotificationChannelName: 'Audiobook Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        audioCacheProvider.overrideWithValue(cache),
      ],
      child: const AudiobookApp(),
    ),
  );
}

class AudiobookApp extends ConsumerStatefulWidget {
  const AudiobookApp({super.key});

  @override
  ConsumerState<AudiobookApp> createState() => _AudiobookAppState();
}

class _AudiobookAppState extends ConsumerState<AudiobookApp> {
  @override
  void initState() {
    super.initState();
    // Eagerly create the coordinator so handler callbacks are wired.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playbackCoordinatorProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Audiobook Reader',
      theme: buildTheme(),
      routerConfig: appRouter(ref),
      debugShowCheckedModeBanner: false,
    );
  }
}
