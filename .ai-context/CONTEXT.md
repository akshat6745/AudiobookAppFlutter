# AI Agent Context — audiobook-app-flutter

Flutter audiobook reader with paragraph-level TTS. Port of a React Native app.
Backend base URL: `lib/services/api_client.dart` → `apiBaseUrl`.

---

## Architecture (3 layers — read before touching audio code)

```
AudiobookHandler   (lib/services/audio_handler.dart)
  └─ owns just_audio.AudioPlayer, emits playbackState/mediaItem (OS notification)
  └─ exposes AudiobookCallbacks: auto-advance, remote next/prev
  └─ NO Riverpod — constructed before runApp, injected via ProviderScope override

PlaybackCoordinator   (lib/providers/playback_coordinator.dart)
  └─ Riverpod glue: registers handler callbacks, loads chapters (offline-first)
  └─ drives playParagraph / playNext / auto-advance across chapters
  └─ eagerly constructed in main.dart via addPostFrameCallback

AudioCacheManager   (lib/services/audio_cache_manager.dart)
  └─ per-paragraph audio cache: memory + temp dir (MP3 remote / WAV on-device)
  └─ lookup order: in-memory → in-flight → OfflineContentService → active TtsEngine
  └─ preload: ultra-priority next-para, char-threshold accumulator, LRU-ish eviction
  └─ singleton injected via ProviderScope override on audioCacheProvider
  └─ DO NOT instantiate a second one
```

**main.dart** constructs `AudioCacheManager` + `AudiobookHandler` before `runApp`,
injects both via `ProviderScope(overrides: [audioCacheProvider.overrideWithValue(...), audioHandlerProvider.overrideWithValue(...)])`.

### TTS engine seam (`lib/services/tts/`)

`AudioCacheManager` never calls a concrete synthesizer directly — it holds a
`TtsEngine` (swappable via `updateEngine()`):
- `RemoteTtsEngine` — online, backend `POST /tts-dual-voice` (MP3). Connectivity-gated:
  throws `TtsOfflineException` immediately when offline instead of waiting out a
  dio timeout.
- `SherpaOnnxTtsEngine` — on-device Kokoro ONNX via `sherpa_onnx` (WAV), runs
  synthesis in a dedicated background isolate (main-isolate synthesis caused
  ANRs). Selected automatically by `activeTtsEngineProvider` once
  `TtsModelManager.installedPaths()` resolves a complete model dir.
- See `lib/services/tts/README.md` and `TTS_ENGINE_RECOMMENDATION.md` for the
  full engine comparison/rationale (Kokoro chosen over Piper/Coqui XTTS/StyleTTS2/MeloTTS).

---

## Critical Invariants

### Paragraph indexing (NEVER change without updating both sides)
- Internal `content` list = `[titleLine, ...backend_paragraphs]`
- `content[0]` = `"Chapter N: Title"` (added by coordinator)
- Audio file mapping: index 0 → `title.mp3`, index k≥1 → `{k-1}.mp3`
- Enforced in: `PlaybackCoordinator.loadChapter`, `AudioCacheManager._loadInternal`

### Voice changes invalidate cache
- Must go through `AudioCacheManager.updateVoices()` — clears memory + disk TTS files
- Never mutate `_narratorVoice`/`_dialogueVoice` directly

### Session-scoped playback (generation counter — prevents cross-chapter audio leaks)
- `AudioCacheManager` cache keys are `(novelSlug, chapterNumber, paragraphIndex)` —
  **not** bare `int` — so the same index in two chapters can never collide.
- Every context change (`setContext` with a new novel/chapter, `updateVoices`,
  `updateEngine`) bumps an internal `_generation` counter **synchronously**, cancels
  the pending preload `Timer`, and fails any in-flight `_activeRequests` completers
  with `_StaleSessionException`.
- Async internals (`_loadAudioForParagraph`, `_loadInternal`, `_pumpPreload`) capture
  `gen = _generation` on entry and re-check `gen == _generation` before writing to
  `_cache` or completing — a late-resolving load from a stale session is discarded,
  never cached, never played.
- `AudiobookHandler` mirrors this with its own `_generation`, bumped by
  `setParagraphs` (new chapter) and `stop()`. `playParagraph` re-checks
  `gen == _generation && paragraphIndex == _currentIndex` after every `await`
  before calling `setAudioSource`/`play` — a stale `playParagraph` call (e.g. from
  auto-advance racing a user tap) never reaches the player.
- `PlaybackCoordinator.loadChapter` calls `_handler.pause()` and resets index state
  **before** any async content resolution, so the reset is atomic from the caller's
  perspective.
- Do not remove the composite key or the generation checks without re-adding
  equivalent protection — this is what fixes the "chapter 5 audio plays under
  chapter 6" bug. Regression tests: `test/audio_cache_preload_test.dart` →
  `chapter switch — session safety` group.

---

## Key Files

| Path | Purpose |
|------|---------|
| `lib/main.dart` | App entry, singleton construction, ProviderScope overrides |
| `lib/router.dart` | go_router config, auth redirect |
| `lib/services/audio_handler.dart` | BaseAudioHandler, just_audio player, generation-guarded `playParagraph`, audio_session interruption/becoming-noisy handling |
| `lib/services/audio_cache_manager.dart` | Composite-keyed, generation-scoped audio cache + preload engine |
| `lib/services/tts/tts_engine.dart` | `TtsEngine` interface, `TtsAudio`, `TtsOfflineException` |
| `lib/services/tts/remote_tts_engine.dart` | Online engine, connectivity-gated |
| `lib/services/tts/sherpa_onnx_tts_engine.dart` | On-device Kokoro engine (isolate-based) |
| `lib/services/tts/tts_model_manager.dart` | Download/extract/locate the Kokoro model archive |
| `lib/services/tts/kokoro_voices.dart` | Voice catalog (28 voices, matches installed model) + presets |
| `lib/services/tts/dual_voice_segmenter.dart` | Narrator/dialogue text segmentation |
| `lib/services/offline_content_service.dart` | Read downloaded content from disk |
| `lib/services/download_service.dart` | Download chapter to disk, poll progress |
| `lib/services/api_client.dart` | Dio client, base URL |
| `lib/services/{novel,chapter,tts,user,download}_api.dart` | Thin API wrappers |
| `lib/providers/audio_providers.dart` | `audioStateProvider`, voice providers, `AudioState` model |
| `lib/providers/playback_coordinator.dart` | `playbackCoordinatorProvider` |
| `lib/providers/tts_engine_provider.dart` | `activeTtsEngineProvider` — picks on-device vs. remote |
| `lib/providers/tts_model_download_provider.dart` | Kokoro model download progress/state |
| `lib/providers/voice_preferences_provider.dart` | `favoriteVoiceIdsProvider`, `recentVoiceIdsProvider` (SharedPrefs-backed) |
| `lib/providers/auth_providers.dart` | `AuthNotifier`, demo fallback (demo/demo) |
| `lib/providers/download_providers.dart` | `DownloadsState`, `downloadsProvider` |
| `lib/providers/progress_providers.dart` | Server-side last-chapter progress |
| `lib/providers/last_position_provider.dart` | Local last paragraph position (SharedPrefs) |
| `lib/screens/reader_screen.dart` | Paragraph list + playback highlight (`.select()`-narrowed watches, bounded `GlobalKey` map) |
| `lib/screens/chapter_list_screen.dart` | Paginated chapter list (`.select()`-narrowed watches) |
| `lib/screens/novel_list_screen.dart` | Library tab (sized `CachedNetworkImage` decoding) |
| `lib/widgets/global_mini_player.dart` | Persistent bottom player bar — no-ops when its route isn't current |
| `lib/widgets/now_playing_modal.dart` | Full now-playing sheet + quick voice presets |
| `lib/widgets/voice_picker.dart` | Voice picker sheet: search, gender/accent filters, favorites, recents, sample playback |
| `lib/widgets/tts_model_download_tile.dart` | On-device model download UI |
| `lib/theme/app_theme.dart` | AppColors constants |

---

## Provider Inventory

```dart
// Injected via ProviderScope overrides (singletons from main.dart)
audioHandlerProvider   Provider<AudiobookHandler>   — read with ref.read (never changes)
audioCacheProvider     Provider<AudioCacheManager>  — read with ref.read (never changes)

// Audio state (UI-facing)
audioStateProvider     StateNotifierProvider<AudioStateNotifier, AudioState>
  AudioState fields: isPlaying, isLoading, currentIndex, novel, chapter, content, playbackSpeed
  Use .select to narrow: only watch fields you render. isPlaying/isLoading NOT needed in
  reader_screen or global_mini_player (those come from handler.playbackState stream).

// Voices
narratorVoiceProvider  StateProvider<String>   default: 'en-US-AvaMultilingualNeural'
dialogueVoiceProvider  StateProvider<String>   default: 'en-GB-RyanNeural'
  Persisted to SharedPreferences on change and restored on app start (main.dart).
favoriteVoiceIdsProvider  StateNotifierProvider<FavoriteVoicesNotifier, List<String>>
  Seeded with am_eric/am_michael/af_heart; supports toggle + reorder; SharedPrefs-backed.
recentVoiceIdsProvider    StateNotifierProvider<RecentVoicesNotifier, List<String>>
  markUsed() pushes to front, dedupes, caps at 6; SharedPrefs-backed.
  Both notifiers expose a `ready` Future — await it in tests before asserting state.

// TTS engine selection
activeTtsEngineProvider   FutureProvider<TtsEngine>
  Resolves SherpaOnnxTtsEngine if a complete Kokoro model is installed, else RemoteTtsEngine.
ttsModelPathsProvider     FutureProvider<TtsModelPaths?>
  From TtsModelManager.installedPaths() — null if no complete model on disk.

// Coordinator
playbackCoordinatorProvider  Provider<PlaybackCoordinator>   ref.read in callbacks

// Auth
authProvider           StateNotifierProvider<AuthNotifier, AuthState>
  AuthState: user (String?), isLoading, error

// Downloads
downloadsProvider      StateNotifierProvider<DownloadsNotifier, DownloadsState>
  DownloadsState: items (List<DownloadedChapter>), active (Map<downloadId, DownloadStatus>), isLoading
  Use .select((s) => ...) to narrow to chapter-specific download status in reader/chapter screens.

// Progress (server-side last chapter per novel slug)
progressProvider       StateNotifierProvider<ProgressNotifier, Map<String, int>>
  Use .select((m) => m[novel.slug]) to avoid rebuilds on other novels' progress changes.

// Last position (local, per-paragraph)
lastPositionProvider   StateNotifierProvider<LastPositionNotifier, Map<String, LastPosition>>
  LastPosition: chapter, paragraph, preview, updatedAt
  Use .select((m) => m[novel.slug]) similarly.

// Backend
backendProvider        StateNotifierProvider<BackendNotifier, BackendConfig>
```

---

## Routing

`go_router` with `ShellRoute` for main tabs. Routes:
- `/login`, `/register` — auth screens
- `/novels` — library (tab 0)
- `/downloads` — downloads (tab 1)
- `/profile` — profile (tab 2)
- `/chapters` — `ChapterListScreen`, receives `Novel` via `state.extra`
- `/reader` — `ReaderScreen`, receives `ReaderArgs` via `state.extra`
  - `ReaderArgs`: novel, chapter, startParagraph?, chapters (List for prev/next nav)

Auth redirect in `router.dart` gates non-auth routes on `authProvider.user`.

---

## Data Models (compact)

```dart
Novel       { slug, title, author?, chapterCount? }
Chapter     { chapterNumber, chapterTitle }
AudioState  { isPlaying, isLoading, currentIndex?, novel?, chapter?, content, playbackSpeed }
DownloadedChapter { downloadId, novelName, chapterNumber, chapterTitle?, status, progress, ... }
DownloadStatus    { downloadId, status (DownloadStatusValue), progress, totalFiles, completedFiles }
LastPosition      { chapter, paragraph, preview, updatedAt }
```

`DownloadStatusValue` enum: `pending | processing | completed | error`

---

## Download flow

1. UI calls `downloadsProvider.notifier.startDownload(DownloadRequest)`
2. `DownloadService` posts to `/download/start`, gets `downloadId`
3. Fire-and-forget poll: `/download/status/{id}` every 5s up to 60 attempts
4. Files land in `${ApplicationDocumentsDirectory}/downloads/{downloadId}/`:
   - `content.json` (paragraphs + chapter_title)
   - `title.mp3` + `{0..N-1}.mp3`
5. Marked `completed` only after file validation (MP3 ≥ 1024 bytes + ID3 header; non-empty paragraphs)
6. `OfflineContentService` reads completed downloads; `AudioCacheManager` checks offline-first

---

## Patterns

### Riverpod select (always use for map/list providers)
```dart
// BAD — rebuilds on any novel's progress change
final progress = ref.watch(progressProvider);
final last = progress[novel.slug];

// GOOD — only rebuilds when this novel's progress changes
final last = ref.watch(progressProvider.select((m) => m[novel.slug]));
```

### Narrow audioStateProvider in screens
```dart
// Only watch fields rendered (excludes isPlaying/isLoading/content/playbackSpeed)
final (:activeIndex, :isThisChapter) = ref.watch(
  audioStateProvider.select((s) => (
    activeIndex: s.currentIndex,
    isThisChapter: s.novel?.slug == novel.slug &&
        s.chapter?.chapterNumber == chapter.chapterNumber,
  )),
);
```

### Handler access
```dart
final handler = ref.read(audioHandlerProvider);  // read, not watch — singleton
```

### Offline-first content load
```dart
final offline = await offlineContentService.getOfflineChapterContent(novelSlug, chapterNumber);
final content = offline?.content ?? (await chapterApi.getChapterContent(...)).content;
```

### go_router navigation with extras
```dart
context.push('/reader', extra: ReaderArgs(novel: novel, chapter: chapter));
context.pushReplacement('/reader', extra: ReaderArgs(...));  // on /reader route already
```

---

## Known Issues / Decisions

- `_ChapterNavButton` in `reader_screen.dart` stores parent `BuildContext` as field — works but fragile pattern
- `audioCacheProvider` body in `audio_providers.dart` (creates new manager from voices) is never executed at runtime because `main.dart` always overrides it — misleading but intentional
- `progressProvider` errors are silently swallowed — no retry UX (pull-to-refresh refreshes it)
- `GlobalMiniPlayer` is intentionally mounted in `MainShell` **and** inside `/chapters` + `/reader` screens (each needs to sit above that screen's own bottom inset). Each instance short-circuits to `SizedBox.shrink()` via `ModalRoute.isCurrent` when it isn't the visible route, so only one is ever actually subscribed/rebuilding — this is the fix, not a bug to re-flag.
- `backend_picker.dart` shows no loading state while switching backends — cosmetic gap
- `now_playing_modal.dart` labels `content[0]` as "Paragraph 0" — it's the chapter title
- `reader_screen.dart` keeps a bounded `GlobalKey` map (`_itemKeys`, pruned to ~80 entries around the active viewport) rather than switching to `ValueKey` — `Scrollable.ensureVisible` needs a `GlobalKey.currentContext`, so the growth-bound approach was used instead of a key-type change
- Kokoro voice catalog (`kokoro_voices.dart`) is deliberately trimmed to the 28 English voices in the installed `kokoro-en-v0_19` model — do not add voices with `sid` ≥ 28 without also switching the downloaded model, they belong to a different (multi-language) checkpoint

---

## SDK Constraints
- Dart `^3.11.5` (records, patterns, named records supported)
- flutter_riverpod `^2.6.1` (StateNotifierProvider, .select(), ref.listen)
- go_router `^14.x`
- just_audio + audio_service for playback
