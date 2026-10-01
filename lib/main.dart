import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/audio_providers.dart';
import 'providers/auth_providers.dart';
import 'providers/playback_coordinator.dart';
import 'providers/progress_providers.dart';
import 'providers/tts_engine_provider.dart';
import 'providers/tts_model_download_provider.dart';
import 'router.dart';
import 'services/api_client.dart';
import 'services/audio_cache_manager.dart';
import 'services/audio_handler.dart';
import 'services/auth_interceptor.dart';
import 'services/session_store.dart';
import 'services/storage.dart';
import 'services/tts/kokoro_voices.dart';
import 'services/tts/remote_tts_engine.dart';
import 'services/tts/tts_engine.dart';
import 'theme/app_theme.dart';
import 'widgets/backend_picker.dart';

/// Attaches the access token to backend requests. Held here so the app widget
/// can register its "token rejected" handler once the router exists.
final _authInterceptor = AuthInterceptor(
  readToken: () => sessionStore.current?.token,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read the stored user before runApp so the router sees the correct auth
  // state on the very first render — prevents the redirect-to-/login race on
  // web refresh and cold app starts.
  // Restore the session (token + username) before runApp so the router sees
  // the correct auth state on the very first render. Identity rests on the
  // token, so a stored username without one counts as signed out.
  final restoredSession = await sessionStore.load();
  final storedUser = restoredSession?.username;

  // Pre-token installs kept a bare username in SharedPreferences, including
  // from the removed `demo`/`demo` bypass. It can't authenticate anything
  // now, so clear it rather than leaving a misleading "signed in" record.
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('auth_user');

  // Attach the token to every backend request. The "token was rejected"
  // handler is registered once the app widget exists (it owns the router) —
  // see _AudiobookAppState.initState.
  apiClient.interceptors.add(_authInterceptor);

  // Resolve the persisted backend URL before any API wrapper fires its
  // first request — apiClient's baseUrl needs to be set up front.
  await loadStoredBackend();

  // Single AudioCacheManager instance shared by handler and providers so the
  // UI reads the same cache that's feeding the player.
  final cache = AudioCacheManager(
    narratorVoice: kOnlineDefaultNarratorVoice,
    dialogueVoice: kOnlineDefaultDialogueVoice,
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
    // The backend rejected our token (expired, or JWT_SECRET was rotated):
    // drop the session and send the user back to sign in, rather than
    // leaving them on a screen where every request fails.
    _authInterceptor.setOnUnauthorized(() async {
      if (ref.read(authProvider).user == null) return; // already signed out
      await ref.read(authProvider.notifier).onUnauthorized();
      _router.go('/login');
    });
    // Eagerly create the coordinator so handler callbacks are wired.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playbackCoordinatorProvider);
      // Auto-provision the offline voice on first launch (Wi-Fi only). Playback
      // uses the remote engine until it lands, then upgrades automatically.
      ref.read(ttsModelDownloadProvider.notifier).maybeAutoStart();
    });
    // Flip the cache's TTS engine to on-device Kokoro once its model is
    // installed (and back to remote otherwise). Defaults to remote until this
    // resolves, so playback is never blocked.
    ref.listenManual(activeTtsEngineProvider, (prev, next) {
      final engine = next.valueOrNull;
      if (engine != null) {
        ref.read(audioCacheProvider).updateEngine(engine);
        _reconcileVoicesForEngine(engine);
      }
    });
    _restoreVoicePrefs();
  }

  /// Kokoro ids (`af_heart`) and edge-tts short names
  /// (`en-US-AvaMultilingualNeural`) are different namespaces. Switching the
  /// active engine can leave the persisted narrator/dialogue choice
  /// meaningless for the *new* engine — e.g. the user downloads the offline
  /// model while an online voice is selected, or forces Online mode while a
  /// Kokoro voice is selected. The on-device engine tolerates this silently
  /// (`KokoroVoices.sidFor` falls back to a default speaker id), but the
  /// remote engine has no such fallback — an unrecognized voice name fails
  /// the whole backend request (this was the "online voices don't work"
  /// bug). Reset to a sensible default for whichever engine just became
  /// active whenever the current choice doesn't belong to it.
  void _reconcileVoicesForEngine(TtsEngine engine) {
    final isOnline = engine is RemoteTtsEngine;
    final narrator = ref.read(narratorVoiceProvider);
    final dialogue = ref.read(dialogueVoiceProvider);
    final narratorOk = KokoroVoices.isKokoro(narrator) != isOnline;
    final dialogueOk = KokoroVoices.isKokoro(dialogue) != isOnline;
    if (narratorOk && dialogueOk) return;

    final newNarrator =
        isOnline ? kOnlineDefaultNarratorVoice : KokoroVoices.defaultNarratorId;
    final newDialogue =
        isOnline ? kOnlineDefaultDialogueVoice : KokoroVoices.defaultDialogueId;
    ref.read(narratorVoiceProvider.notifier).state = newNarrator;
    ref.read(dialogueVoiceProvider.notifier).state = newDialogue;
    ref.read(audioCacheProvider).updateVoices(newNarrator, newDialogue);
  }

  /// Restores the narrator/dialogue voice the user last picked (persisted in
  /// [StorageKeys.narratorVoice]/[dialogueVoice]), then keeps them in sync on
  /// every future change. Runs after the providers already exist with their
  /// hardcoded defaults, so the cache — constructed before `runApp` with
  /// those same defaults — is explicitly resynced once the real preference
  /// is known.
  Future<void> _restoreVoicePrefs() async {
    final storedNarrator = await Storage.getString(StorageKeys.narratorVoice);
    final storedDialogue = await Storage.getString(StorageKeys.dialogueVoice);
    if (!mounted) return;

    if (storedNarrator != null || storedDialogue != null) {
      final String narrator = storedNarrator ?? ref.read(narratorVoiceProvider);
      final String dialogue = storedDialogue ?? ref.read(dialogueVoiceProvider);
      ref.read(narratorVoiceProvider.notifier).state = narrator;
      ref.read(dialogueVoiceProvider.notifier).state = dialogue;
      await ref.read(audioCacheProvider).updateVoices(narrator, dialogue);
    }
    if (!mounted) return;

    // Restoring a persisted voice can reintroduce a mismatch with whichever
    // engine actually resolves (e.g. a Kokoro voice restored while the
    // resolved engine turns out to be online) — reconcile once more against
    // the engine's *final* resolution so correctness doesn't depend on which
    // of these two async paths (voice-pref restore vs. engine resolution)
    // happens to finish first.
    final engine = await ref.read(activeTtsEngineProvider.future);
    if (!mounted) return;
    _reconcileVoicesForEngine(engine);

    ref.listenManual(narratorVoiceProvider, (prev, next) {
      Storage.setString(StorageKeys.narratorVoice, next);
    });
    ref.listenManual(dialogueVoiceProvider, (prev, next) {
      Storage.setString(StorageKeys.dialogueVoice, next);
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
      // Keep the children list shape stable across rebuilds — falling
      // back to a const placeholder when `child` is briefly null avoids
      // child slots shifting (which makes Flutter rebuild/reparent the
      // BackendPickerOverlayButton between Stack positions and triggers
      // assertions like `_dependents.isEmpty`).
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
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
