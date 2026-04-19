# Flutter Audiobook App — Session Handoff

## Why this project exists

This is a **Flutter rewrite** of the React Native app at
`/Users/aaggarwal/Desktop/Projects/audiobook-mobile`.

The RN app's core audio flow works, but **Android notification Play/Pause/Next/Previous
controls are unreliable** under React Native's New Architecture (Fabric). Root cause:
`react-native-track-player` v4.1.2's event/state propagation breaks in subtle ways with
the new renderer — `playback-state` and `playback-queue-ended` events don't fire
reliably, which forced a 500ms `getProgress()` polling workaround and multiple
`isTransitioning` / `suppressPauseEvents` / `operationLock` flags that still miss
events. We tried twice to fix it in RN (including a full refactor to a `GlobalAudioState`
singleton) — still broken.

This Flutter rewrite uses **`just_audio` + `audio_service`**, which drives Android
MediaSession natively and fires `playerStateStream` events reliably. No polling hack
needed.

Full feature spec + migration rationale: see `FEATURES.md` in this directory.

## Architecture

| Layer | Package |
|-------|---------|
| Audio playback | `just_audio` |
| Notification / lock-screen MediaSession | `audio_service` |
| State management | `flutter_riverpod` |
| HTTP | `dio` |
| Navigation | `go_router` (ShellRoute with bottom nav + persistent mini player) |
| Persisted KV | `shared_preferences` |
| Secure KV | `flutter_secure_storage` |
| File system | `path_provider` + `dart:io` |
| Image cache | `cached_network_image` |
| Deep links | `app_links` |
| Home widget (deferred) | `home_widget` |

Backend API: `https://audiobook-python.onrender.com` — unchanged from the RN app.
All endpoints documented in `FEATURES.md` §2.

## Folder layout

```
lib/
├── main.dart                        AudioService.init + ProviderScope
├── router.dart                      go_router config
├── theme/app_theme.dart
├── models/                          novel, chapter, downloaded_chapter, paragraph_audio, user_progress
├── services/
│   ├── api_client.dart              dio base
│   ├── novel_api.dart / chapter_api.dart / tts_api.dart / user_api.dart / download_api.dart
│   ├── audio_handler.dart           AudiobookHandler extends BaseAudioHandler — the player
│   ├── audio_cache_manager.dart     port of RN preload strategy
│   ├── offline_content_service.dart
│   ├── download_service.dart
│   └── storage.dart                 SharedPreferences wrapper + key constants
├── providers/
│   ├── audio_providers.dart         audioHandler/audioCache/audioState
│   ├── playback_coordinator.dart    high-level playback orchestration
│   ├── auth_providers.dart          login/register/logout via secure storage
│   ├── download_providers.dart
│   └── progress_providers.dart
├── screens/                         login, register, main_shell, novel_list, chapter_list, reader, downloads, profile
└── widgets/global_mini_player.dart
```

## Key invariants (carried over from RN)

1. **Paragraph index mapping:** `content[0]` is the chapter title (client-side
   prepended as `"Chapter {N}: {Title}"`). Paragraph index `k ≥ 1` maps to the
   backend's paragraph `k-1`. Offline audio files: `title.mp3` for index 0,
   `{k-1}.mp3` for index k ≥ 1.

2. **Download layout:** `${ApplicationDocumentsDirectory}/downloads/{downloadId}/`
   containing `content.json`, `title.mp3`, `0.mp3`…`{N-1}.mp3`.

3. **Preload strategy** (ported to `audio_cache_manager.dart`):
   - Ultra-priority: immediate-next paragraph fires zero-delay fire-and-forget.
   - Speed-adaptive: distance = `maxPreloadDistance * min(speed, 2.5)`, delay = 0ms for speed ≥ 1.5.
   - Character threshold: keep loading until `Σ chars ≥ preloadCharacterThreshold` (default 3000).
   - Eviction: keep indices in `[currentIndex - 3, currentIndex + maxPreloadDistance]`; delete older files from disk.

4. **Offline-first lookup** in cache manager: in-memory → in-flight request → downloaded files on disk (indexed by `{paragraphIndex == 0 ? titleAudio : paragraphAudios[paragraphIndex-1]}`) → TTS API call.

5. **Voice change invalidates entire cache** (mem + disk TTS temp files).

## Current state

| Status | Item |
|--------|------|
| ✅ | `flutter analyze` — 0 errors, only style infos |
| ✅ | `flutter build apk --debug` — succeeded, APK at `build/app/outputs/flutter-apk/app-debug.apk` (~161MB debug) |
| ✅ | `flutter install --debug` — installed to connected emulator |
| ❓ | **Not yet tested on a real device** with actual playback + notification controls |
| ❌ | Home widget (Android `home_widget` + XML layout) — deferred to v2 |
| ❌ | Release APK build / iOS config (never attempted) |
| ❌ | No unit or widget tests written |

## What's next

1. **Manual test on device/emulator** — the whole point of this rewrite. Verify:
   - Login with demo/demo works (offline fallback in `auth_providers.dart`).
   - Novel list loads + tap opens chapters.
   - Tap a paragraph → plays, active-paragraph highlight moves, auto-scrolls.
   - Auto-advance between paragraphs (should be gap-less).
   - Auto-advance to next chapter at end.
   - **Notification shade Play/Pause/Next/Previous actually work** (this is the whole reason we rewrote).
   - Speed change from bottom-sheet settings takes effect live.
   - Download a chapter; play it offline (kill wifi).

2. **Fix anything that surfaces during device testing.**

3. **Home widget** (later) — `home_widget` package, XML layout in `android/app/src/main/res/layout/widget_layout.xml`, `AudiobookWidgetProvider.kt`. RN version had play/pause/next/prev/speed controls.

4. **iOS config** — `ios/Runner/Info.plist` needs `UIBackgroundModes` entry (`audio`) for background playback; `audio_service` README has the exact config.

5. **Release build** (`flutter build apk --release`) when ready for real users.

## Files to look at first

- `FEATURES.md` — full technical spec (16 sections: architecture, API, models, audio engine, cache strategy, download layout, lifecycle, etc.)
- `lib/services/audio_handler.dart` — the most important file; drives `just_audio` and publishes MediaSession state.
- `lib/services/audio_cache_manager.dart` — the preload engine.
- `lib/providers/playback_coordinator.dart` — glue between UI and handler (auto-advance logic lives here).
- `lib/main.dart` — `AudioService.init` + Riverpod overrides.

## Important gotcha

`audioHandlerProvider` throws `UnimplementedError` if accessed before `main.dart` overrides it in `ProviderScope`. This is intentional — the handler is created asynchronously via `AudioService.init()` and injected once ready. If you add a new provider that depends on the handler, it's fine — just don't read it inside `main()` before `AudioService.init()` resolves.

## Build / run commands

```sh
# From this directory:
flutter pub get
flutter analyze
flutter run                       # debug with hot reload (best for dev)
flutter build apk --debug         # produces build/app/outputs/flutter-apk/app-debug.apk
flutter install --debug           # installs the debug APK to connected device
flutter build apk --release       # smaller APK (20-30MB), use when shipping
```

## Original RN project for reference

`/Users/aaggarwal/Desktop/Projects/audiobook-mobile` — the React Native app we ported
from. If behavior differs from expectation, check there for the "source of truth"
logic, especially:
- `src/services/AudioCacheManager.ts` — the preload algorithm we copied.
- `src/services/downloadService.ts` — download / validation / resume logic.
- `src/services/api.ts` — API endpoint list.
- `src/context/AudioContext.tsx` — RN equivalent of `PlaybackCoordinator`.
