import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/audio_providers.dart';
import 'providers/auth_providers.dart';
import 'providers/playback_coordinator.dart';
import 'router.dart';
import 'services/audio_cache_manager.dart';
import 'services/audio_handler.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read the stored user before runApp so the router sees the correct auth
  // state on the very first render — prevents the redirect-to-/login race on
  // web refresh and cold app starts.
  final prefs = await SharedPreferences.getInstance();
  final storedUser = prefs.getString('auth_user');

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
      androidStopForegroundOnPause: false,
    ),
  );

  // Configure the audio session for spoken-word content so the OS knows to
  // duck (lower volume) for transient sounds instead of pausing playback.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        audioCacheProvider.overrideWithValue(cache),
        authProvider.overrideWith((_) => AuthNotifier(initialUser: storedUser)),
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
