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
  └─ per-paragraph MP3 cache: memory + temp dir
  └─ lookup order: in-memory → in-flight → OfflineContentService → POST /tts-dual-voice
  └─ preload: ultra-priority next-para, speed-adaptive distance, char-threshold, LRU eviction
  └─ singleton injected via ProviderScope override on audioCacheProvider
  └─ DO NOT instantiate a second one
```

**main.dart** constructs `AudioCacheManager` + `AudiobookHandler` before `runApp`,
injects both via `ProviderScope(overrides: [audioCacheProvider.overrideWithValue(...), audioHandlerProvider.overrideWithValue(...)])`.

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

---

## Key Files

| Path | Purpose |
|------|---------|
| `lib/main.dart` | App entry, singleton construction, ProviderScope overrides |
| `lib/router.dart` | go_router config, auth redirect |
| `lib/services/audio_handler.dart` | BaseAudioHandler, just_audio player |
| `lib/services/audio_cache_manager.dart` | MP3 cache + preload engine |
| `lib/services/offline_content_service.dart` | Read downloaded content from disk |
| `lib/services/download_service.dart` | Download chapter to disk, poll progress |
| `lib/services/api_client.dart` | Dio client, base URL |
| `lib/services/{novel,chapter,tts,user,download}_api.dart` | Thin API wrappers |
| `lib/providers/audio_providers.dart` | `audioStateProvider`, voice providers, `AudioState` model |
| `lib/providers/playback_coordinator.dart` | `playbackCoordinatorProvider` |
| `lib/providers/auth_providers.dart` | `AuthNotifier`, demo fallback (demo/demo) |
| `lib/providers/download_providers.dart` | `DownloadsState`, `downloadsProvider` |
| `lib/providers/progress_providers.dart` | Server-side last-chapter progress |
| `lib/providers/last_position_provider.dart` | Local last paragraph position (SharedPrefs) |
| `lib/screens/reader_screen.dart` | Paragraph list + playback highlight |
| `lib/screens/chapter_list_screen.dart` | Paginated chapter list |
| `lib/screens/novel_list_screen.dart` | Library tab |
| `lib/widgets/global_mini_player.dart` | Persistent bottom player bar |
| `lib/widgets/now_playing_modal.dart` | Full now-playing sheet |
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
- `GlobalMiniPlayer` appears in both `MainShell` (stack overlay) and inside `/chapters` + `/reader` screens — the shell stays mounted underneath, so check for double-render if profiling shows issue
- `backend_picker.dart` shows no loading state while switching backends — cosmetic gap
- `now_playing_modal.dart` labels `content[0]` as "Paragraph 0" — it's the chapter title

---

## SDK Constraints
- Dart `^3.11.5` (records, patterns, named records supported)
- flutter_riverpod `^2.6.1` (StateNotifierProvider, .select(), ref.listen)
- go_router `^14.x`
- just_audio + audio_service for playback
