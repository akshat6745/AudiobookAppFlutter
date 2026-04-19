# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter audiobook reader with paragraph-level TTS playback. This is a port of a React Native app (`audiobook-mobile`) — see `FEATURES.md` for the full feature spec / porting blueprint, including the exhaustive endpoint list, data-model invariants, and the "what we're explicitly NOT porting" section (RNTP workarounds, completion polling, operationLock flags — all unnecessary under `just_audio` + `audio_service`).

## Commands

```bash
flutter pub get                      # install deps
flutter run                          # debug run (auto-detects device)
flutter run -d <device-id>           # target a specific device (`flutter devices` to list)
flutter analyze                      # lint (rules via analysis_options.yaml → flutter_lints)
flutter test                         # run tests (test/ is currently empty)
flutter test test/path/to_test.dart  # single test file
flutter test --name "pattern"        # filter by test name
flutter build apk                    # release APK
flutter build ios                    # iOS release
```

SDK constraint: Dart `^3.11.5` (see `pubspec.yaml`). Backend base URL is hardcoded in `lib/services/api_client.dart` (`apiBaseUrl`).

## Architecture

### Playback pipeline — three layers

Understanding how these layers pass control is essential before touching audio code:

1. **`AudiobookHandler`** (`lib/services/audio_handler.dart`) — `audio_service.BaseAudioHandler` subclass that owns the single `just_audio.AudioPlayer`. It is the MediaSession source of truth and emits `playbackState` / `mediaItem` for the OS notification + lock screen. It exposes a narrow `AudiobookCallbacks` contract (auto-advance, remote next/prev) rather than reaching into providers directly — this keeps the handler independent of Riverpod and safe to construct before `runApp`.
2. **`PlaybackCoordinator`** (`lib/providers/playback_coordinator.dart`) — Riverpod-wired glue that registers callbacks on the handler, loads chapters (offline-first via `OfflineContentService`, then `chapterApi`), prepends the title line to the paragraph list, and drives `playParagraph` / `playNext` / auto-advance across chapter boundaries. Eagerly constructed in `main.dart` via `addPostFrameCallback` so callbacks are wired before any playback begins.
3. **`AudioCacheManager`** (`lib/services/audio_cache_manager.dart`) — per-paragraph MP3 cache (memory + temp dir). Offline-first lookup order: in-memory → in-flight request → `OfflineContentService.getOfflineChapterAudio` → `POST /tts-dual-voice`. Preload engine does ultra-priority next-paragraph load, speed-adaptive distance (`min(speed, 2.5)` multiplier), character-threshold accumulator (3000 chars default), and LRU-ish eviction keeping `[currentIndex - 3, currentIndex + maxPreloadDistance]`.

`main.dart` constructs a single `AudioCacheManager` and a single `AudiobookHandler` before `runApp`, then injects both via `ProviderScope` overrides on `audioCacheProvider` / `audioHandlerProvider`. **Do not instantiate a second cache manager** — the UI and handler must read the same cache instance.

### Critical invariant: paragraph indexing

From `FEATURES.md` §3 and enforced in `PlaybackCoordinator.loadChapter`:

- Client's internal `content` list is `[titleLine, ...backend_paragraphs]` → **`content[0]` is the chapter title** (`"Chapter {N}: {Title}"`).
- Offline audio file mapping: paragraph `0` → `title.mp3`; paragraph `k ≥ 1` → `{k-1}.mp3`. This off-by-one is deliberate; `AudioCacheManager._loadInternal` already implements it. Preserve this mapping whenever touching cache/download/reader code.

### State management

Riverpod everywhere. Providers are topic-organized under `lib/providers/`:
- `audio_providers.dart` — `audioStateProvider` (UI-facing `AudioState`), `audioHandlerProvider` (override-injected), `audioCacheProvider` (override-injected), voice providers.
- `playback_coordinator.dart` — the coordinator provider; eagerly read in `main.dart` to wire handler callbacks at app start.
- `auth_providers.dart` — `AuthNotifier` with demo-mode fallback (username/password `demo`/`demo`) and `flutter_secure_storage`-backed session restore.
- `download_providers.dart`, `progress_providers.dart` — downloads + per-novel last-chapter tracking.

### Routing

`go_router` with a `ShellRoute` for the main tabs (`/novels`, `/downloads`, `/profile`) and top-level routes for `/login`, `/register`, `/chapters`, `/reader`. Auth redirect in `router.dart` gates non-auth routes on `authProvider.user`. `ChapterListScreen` and `ReaderScreen` receive their domain objects via `state.extra` (Novel / ReaderArgs) — not path params — so any deep-link entry must materialize those objects first.

### Networking

`dio`-based. Single `apiClient` in `lib/services/api_client.dart`; each resource has its own thin wrapper (`novel_api`, `chapter_api`, `tts_api`, `user_api`, `download_api`). Login has a network-failure path that accepts `demo`/`demo` as a last-resort bypass.

### Downloads

`DownloadService` (singleton, `lib/services/download_service.dart`) downloads a chapter into `${ApplicationDocumentsDirectory}/downloads/{downloadId}/` as `content.json` + `title.mp3` + `{0..N-1}.mp3`. Backend progress 0–50%, local file download 50–100%. Polls `/download/status/{id}` every 5s up to 60 attempts. Per-file retry delays `[0, 1000, 3000]ms`, max 5 concurrent paragraph downloads. Records persist in `SharedPreferences` under `StorageKeys.downloadedChapters` and are read back by `OfflineContentService` to resolve offline content.

Local status is only flipped to `completed` after files are validated on disk (MP3 ≥ 1024 bytes + ID3 / MPEG sync header; `content.json` non-empty `paragraphs[]` with `chapter_title`). This ordering avoids a race with `AudioCacheManager` — don't mark completed before validation.

### Voice changes invalidate the cache

`AudioCacheManager.updateVoices` clears both the in-memory map and the on-disk TTS temp files. Any flow that changes narrator/dialogue voice must go through this method — don't mutate the voice fields directly.

## Workflow expectations (from user's global CLAUDE.md)

- Enter plan mode for any non-trivial change (3+ steps or architectural decisions). Re-plan when something goes sideways rather than pushing through.
- Prefer subagents for research / parallel exploration to keep the main context clean.
- Verify changes before marking done; don't claim success without proof.
- Simplicity first — minimal, targeted diffs; no "quick fix" cop-outs on architectural issues.
