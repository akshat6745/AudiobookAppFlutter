# Speaking Books

A Flutter audiobook reader with paragraph-level TTS playback. Converts written novels into spoken audio on-demand using a dual-voice TTS backend (narrator + dialogue), with offline download support and OS media session integration.

## Features

- Paragraph-level TTS playback with auto-advance across chapter boundaries
- Dual-voice synthesis (narrator voice + dialogue voice, configurable)
- Offline downloads — chapters stored locally as MP3s + JSON for offline reading
- Background playback with lock screen / notification controls (Android & iOS)
- Speed-adaptive preload engine with LRU cache
- Persistent login across sessions and web refreshes
- Runs on Android, iOS, and Web

## Architecture

Three-layer audio pipeline:

| Layer | File | Responsibility |
|---|---|---|
| `AudiobookHandler` | `lib/services/audio_handler.dart` | Owns the `just_audio` player, drives MediaSession via `audio_service` |
| `PlaybackCoordinator` | `lib/providers/playback_coordinator.dart` | Riverpod glue — loads chapters, wires callbacks, handles chapter boundaries |
| `AudioCacheManager` | `lib/services/audio_cache_manager.dart` | Per-paragraph MP3 cache (memory + disk on mobile, data URIs on web), preload engine |

State management: Riverpod throughout. Routing: `go_router` with auth-gated shell route.

## Getting Started

### Prerequisites

- Flutter SDK `>=3.11.5`
- A running instance of the [audiobook backend](https://github.com/akshataggarwal/audiobook-python) (or the hosted URL)

### Setup

```bash
flutter pub get
```

Set the API base URL in `lib/services/api_client.dart`:

```dart
const String apiBaseUrl = 'https://your-backend-url.com';
```

### Run

```bash
flutter run                      # auto-detect device
flutter run -d chrome            # web
flutter run -d <device-id>       # specific device (flutter devices to list)
```

### Build

```bash
flutter build apk                # Android APK
flutter build appbundle          # Android AAB (Play Store)
flutter build ios                # iOS (requires Xcode)
flutter build web                # Web
```

### Lint & Tests

```bash
flutter analyze
flutter test
```

## Deployment Checklist

Before shipping to production:

- [ ] **API URL** — switch `apiBaseUrl` in `lib/services/api_client.dart` from `localhost` to the production endpoint
- [ ] **Android signing** — create a release keystore and configure `signingConfigs` in `android/app/build.gradle.kts` (currently using debug key)
- [ ] **iOS provisioning** — verify bundle ID and provisioning profile in Xcode before archiving
- [ ] **Demo credentials** — decide whether to gate `demo`/`demo` login behind `kDebugMode` for prod builds
- [ ] **Web CORS** — ensure the backend allows requests from the web deployment origin
- [ ] **Web manifest** — `web/manifest.json` name/description fields

## Project Structure

```
lib/
  main.dart                    # App entry point, provider overrides
  router.dart                  # go_router config with auth redirect
  models/                      # Data models (Novel, Chapter, ParagraphAudio…)
  providers/                   # Riverpod providers + PlaybackCoordinator
  screens/                     # UI screens
  services/                    # API clients, audio handler, cache, downloads
  theme/                       # App theme
```

## Key Invariants

- `content[0]` is always the chapter title line; backend paragraphs start at index 1.
- Offline audio mapping: paragraph `0` → `title.mp3`; paragraph `k ≥ 1` → `{k-1}.mp3`.
- On web, audio is served as in-memory `data:audio/mpeg;base64,...` URIs (no file system).
- Voice changes must go through `AudioCacheManager.updateVoices()` to invalidate the cache.
- Do not instantiate a second `AudioCacheManager` — the handler and UI share one instance injected via `ProviderScope`.
