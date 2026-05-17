import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/audio_providers.dart';
import 'providers/auth_providers.dart';
import 'providers/playback_coordinator.dart';
import 'providers/progress_providers.dart';
import 'router.dart';
import 'services/api_client.dart';
import 'services/audio_cache_manager.dart';
import 'services/audio_handler.dart';
import 'theme/app_theme.dart';
import 'widgets/backend_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read the stored user before runApp so the router sees the correct auth
  // state on the very first render — prevents the redirect-to-/login race on
  // web refresh and cold app starts.
  final prefs = await SharedPreferences.getInstance();
  final storedUser = prefs.getString('auth_user');

  // Resolve the persisted backend URL before any API wrapper fires its
  // first request — apiClient's baseUrl needs to be set up front.
  await loadStoredBackend();

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

class _AudiobookAppState extends ConsumerState<AudiobookApp>
    with WidgetsBindingObserver {
  /// The router holds a `GlobalKey<NavigatorState>` (`rootNavigatorKey`).
  /// Building a fresh `GoRouter` on every `build()` call would attach that
  /// same key to a new Navigator before the old one has been torn down —
  /// which manifests as "Duplicate GlobalKeys detected in widget tree"
  /// (with `_OverlayEntryWidgetState` keys) the next time anything causes
  /// the root widget to rebuild (keyboard open, orientation change,
  /// dialog open/close, etc.). Cache the router for the app's lifetime.
  late final _router = appRouter(ref);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Eagerly create the coordinator so handler callbacks are wired.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playbackCoordinatorProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // On Android, the user may have listened on another device or via the
    // notification while the app was backgrounded. Re-sync progress on
    // resume so the chapter list / "Continue Reading" badges update
    // without a manual refresh. The provider throttles itself, so this is
    // safe to call on every resume.
    if (state == AppLifecycleState.resumed) {
      ref.read(progressProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Audiobook Reader',
      theme: buildTheme(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Stack(
        children: [
          ?child,
          // Pinned bottom-left so the icon stays clear of the usual top
          // action zone (back button, prev/next, download) and clear of
          // the bottom nav + mini player.
          const Positioned(
            left: 8,
            bottom: 96,
            child: BackendPickerOverlayButton(),
          ),
        ],
      ),
    );
  }
}
