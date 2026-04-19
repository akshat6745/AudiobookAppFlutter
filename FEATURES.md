# AudiobookApp — Flutter Rewrite Feature Spec

Complete blueprint of the React Native app (`audiobook-mobile`) to be reproduced in Flutter with `just_audio` + `audio_service`.

## 1. High-level Architecture

| Layer | RN (current) | Flutter (target) |
|-------|--------------|------------------|
| State | React Context + singleton | Riverpod (global providers) |
| HTTP | axios | dio |
| Audio playback | react-native-track-player | just_audio + audio_service |
| Audio duration | expo-av | just_audio (built-in) |
| File system | expo-file-system | path_provider + dart:io |
| Persisted KV | AsyncStorage | shared_preferences |
| Secure KV | expo-secure-store | flutter_secure_storage |
| Notifications / lock screen | RNTP internal | audio_service (native MediaSession) |
| Android widget | react-native-android-widget | home_widget |
| Deep links | Linking | app_links |
| Image cache | React Native Image | cached_network_image |

## 2. Backend API

Base URL: `https://audiobook-python.onrender.com` (override per-env).

### Endpoints used

| Method | Path | Purpose | Notes |
|--------|------|---------|-------|
| GET | `/novels?username={u}` | List novels | Returns `Novel[]` |
| POST | `/upload-epub` | Upload EPUB | multipart/form-data |
| GET | `/chapters-with-pages/{novelSlug}?page={n}` | Paginated chapters | `{chapters, total_pages, current_page}` |
| GET | `/chapter?chapterNumber={n}&novelName={slug}` | Chapter content | `{content: string[], chapterTitle, chapterNumber}` |
| POST | `/tts-dual-voice` | Single paragraph TTS | Body `{text, paragraphVoice, dialogueVoice}`, returns MP3 bytes |
| GET | `/novel-with-tts?novelName=..&chapterNumber=..&voice=..&dialogueVoice=..` | Full chapter MP3 | Pre-generated |
| GET | `/novel/{slug}/cover` | Novel cover image | Direct image bytes |
| GET | `/novel/{slug}/image/{imageId}` | Inline image | Direct bytes |
| POST | `/userLogin` | Login | `{username, password}` |
| POST | `/register` | Register | `{username, password}` |
| POST | `/user/progress` | Save progress | `{username, novelName, lastChapterRead}` |
| GET | `/user/progress?username={u}` | Get progress list | `{progress: UserProgress[]}` |
| GET | `/user/progress/{novelSlug}?username={u}` | Single progress | `UserProgress` |
| POST | `/download/chapter` | Start chapter download | `{novel_name, chapter_number, narrator_voice, dialogue_voice}` |
| GET | `/download/status/{id}` | Download job status | `DownloadStatus` |
| GET | `/download/{id}/files` | List generated files | `string[]` |
| GET | `/download/file/{id}/{filename}` | Download single file | MP3 or JSON |
| GET | `/health` | Health check | `{status}` |

Demo fallback: if network fails, allow username `"demo"` / password `"demo"` with hardcoded novels.

## 3. Data Models

### Novel
```dart
class Novel {
  final String id;
  final String title;
  final String? author;
  final int? chapterCount;
  final NovelSource source; // cloudflare_d1 | google_doc | epub_upload
  final String slug;
  final String? description;
  final bool isPublic;
}
```

### Chapter
```dart
class Chapter {
  final int chapterNumber;
  final String chapterTitle;
  final String? id;
  final int? wordCount;
}
```

### ChapterContent
```dart
class ChapterContent {
  final List<String> content;      // paragraph texts (index 0 is NOT the title — title inserted client-side)
  final int? chapterNumber;
  final String? chapterTitle;
}
```

**CRITICAL invariant:** In the client's internal `content` list, **`content[0]` is the chapter title** (prepended as `"Chapter {N}: {Title}"`). Paragraph indices 1..N map to the backend's 0..N-1 content array. Offline audio index mapping:
- paragraphIndex `0` → `title.mp3`
- paragraphIndex `k` (k ≥ 1) → `{k-1}.mp3`

### UserProgress
```dart
class UserProgress {
  final String novelName;   // slug
  final int lastChapterRead;
  final DateTime? lastReadDate;
}
```

### DownloadedChapter (persisted in SharedPreferences)
```dart
class DownloadedChapter {
  final String downloadId;
  final String novelName;
  final int chapterNumber;
  final String? chapterTitle;
  final DownloadStatus status; // pending | processing | completed | error
  final double progress;       // 0..100
  final DateTime downloadDate;
  final int totalFiles;
  final int completedFiles;
}
```

## 4. Audio Engine

### Requirements
- Paragraph-level playback (one paragraph = one audio file)
- Auto-advance to next paragraph with ~0 gap
- Auto-advance to next chapter at end
- Playback speed 0.25x–4.0x (clamped, pitch-corrected)
- **Notification / lock screen** controls: Play, Pause, Next, Previous, Stop
- Works backgrounded, survives app kill (on Android)
- Offline-first: use downloaded MP3 if available
- Speed-adaptive preloading

### just_audio + audio_service design

Use `audio_service.AudioHandler` as the single source of truth. The handler owns a `just_audio.AudioPlayer` and exposes lifecycle + playback APIs.

```dart
class AudiobookHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  AudioCacheManager cache;
  List<String> paragraphs = const [];
  int? currentIndex;

  // Auto-advance: listen to _player.playerStateStream
  //   when processingState == completed → _onParagraphEnded()
  //
  // No polling. audio_service + just_audio fire playerStateStream
  // reliably on both Android and iOS. This fixes the RNTP
  // completion-event bug that forced the 500ms polling workaround.
}
```

Integration points:
- `MediaItem` supplies notification metadata (title, album, artist, artUri).
- Remote controls (`play()`, `pause()`, `skipToNext()`, `skipToPrevious()`, `stop()`) map directly to MediaSession callbacks.
- No headless-task glue needed (audio_service spans JS ↔ native transparently).

## 5. Audio Cache Manager

Port the RN version 1:1. In-memory `Map<int, ParagraphAudioData>` + on-disk MP3 files in the app cache directory.

### ParagraphAudioData
```dart
class ParagraphAudioData {
  final int paragraphIndex;
  final String paragraphText;
  bool audioReceived;
  String? audioUri;       // file:// path
  Duration? duration;
  bool isLoading;
  final DateTime createdAt;
  final int characterCount;
}
```

### Config
```dart
class AudioCacheConfig {
  final int maxCacheSize;            // default 30
  final int preloadCharacterThreshold; // default 3000
  final int maxPreloadDistance;      // default 15
  final Duration cacheExpiry;        // default 30 min
}
```

### Preload strategy
1. **Ultra-priority next paragraph** — zero-delay load of `currentIndex + 1` (fire-and-forget).
2. **Speed-adaptive distance** — multiply `maxPreloadDistance` by `min(speed, 2.5)`.
3. **Speed-adaptive delay** — 0ms for speed ≥ 1.5, else 1ms.
4. **Character threshold** — keep loading ahead until `Σ character_count ≥ preloadCharacterThreshold` OR adaptive distance reached.
5. **Eviction** — keep indices in `[currentIndex - 3, currentIndex + maxPreloadDistance]`. Evict others; delete their files.

### Background preload
On `AppLifecycleState.paused`, fire `preloadAhead(currentIndex, 15)` so offline audio is ready if user backgrounds during playback.

### Offline-first lookup order
1. In-memory cache (valid entry)
2. In-flight request (await it)
3. `OfflineContentService.getOfflineChapterAudio(novel, chapter)` — returns `{titleAudio?, paragraphAudios: (String?)[]}`
4. TTS API call `POST /tts-dual-voice` → save to file → cache

Missing paragraph in offline set → `null` → individual TTS fallback (don't fail whole chapter).

### Voice change invalidation
`updateVoices(narrator, dialogue)` clears the full cache (both memory and disk files).

## 6. Download Service

Port of `downloadService.ts`. Key invariants:
- **Base dir**: `${ApplicationDocumentsDirectory}/downloads/{downloadId}/`
- **File layout**:
  - `content.json` — `{chapter_title, paragraphs: string[]}`
  - `title.mp3` — chapter title audio
  - `{i}.mp3` for each paragraph `0..N-1`
- **Status poll loop** — 5s interval, 60 max attempts (5 min timeout)
- **Backend status**: `pending | processing | completed | error`
- **Local status**: don't mark `completed` until files verified on disk (avoids race with AudioCacheManager)
- **Concurrent file downloads**: max 5 paragraph files in parallel, each with retry `[0, 1000, 3000]ms`
- **Resume support**: before downloading each file, stat + validate; skip if valid
- **Validation**:
  - MP3: size ≥ 1024 bytes, ID3 tag (`"ID3"`) or MPEG sync word (`0xFFE0`) in first 4 bytes
  - content.json: non-empty `paragraphs[]`, has `chapter_title`
- **Storage quota**: check `≥ 50 MB` free via `DiskSpacePlus` or `path_provider + statfs`
- **Progress scale**: 0–50% for backend processing, 50–100% for local file download

## 7. Global State (Riverpod)

```dart
// Core playback state (mirrors RN GlobalAudioState)
@freezed
class AudioState with _$AudioState {
  const factory AudioState({
    @Default(false) bool isPlaying,
    int? currentParagraphIndex,
    int? currentChapterNumber,
    @Default(false) bool isLoading,
    @Default(1.0) double playbackSpeed,
  }) = _AudioState;
}

final audioStateProvider = StateNotifierProvider<AudioStateNotifier, AudioState>(...)
final audioHandlerProvider = Provider<AudiobookHandler>(...)
final audioCacheProvider = Provider<AudioCacheManager>(...)

// Chapter/novel context
final currentNovelProvider = StateProvider<Novel?>((_) => null);
final currentChapterProvider = StateProvider<Chapter?>((_) => null);
final chapterContentProvider = StateProvider<List<String>>((_) => []);

// Voice preferences (persisted)
final narratorVoiceProvider = StateProvider<String>((_) => 'en-US-AvaMultilingualNeural');
final dialogueVoiceProvider = StateProvider<String>((_) => 'en-US-RyanNeural');

// Auth
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(...)

// Downloads
final downloadsProvider = StateNotifierProvider<DownloadsNotifier, DownloadsState>(...)

// Progress
final progressProvider = StateNotifierProvider<ProgressNotifier, Map<String, int>>(...)
```

## 8. Screens & Navigation

Use `go_router` with nested shells.

```
/login
/register
/  (shell with BottomNavigationBar)
├── /novels           (NovelListScreen)
│   └── /novels/:slug (ChapterListScreen)
│       └── /novels/:slug/chapter/:num (ReaderScreen)
├── /downloads        (DownloadsScreen)
└── /profile          (ProfileScreen)
```

`GlobalMiniPlayer` is a shell-level widget (always visible when `currentParagraphIndex != null`).

### Screen inventory

1. **LoginScreen** — username/password, demo mode, gradient bg. Depends: `authProvider`.
2. **RegisterScreen** — signup with password confirmation + length validation.
3. **NovelListScreen** — search bar, FlatList-equivalent (`ListView.builder`), pull to refresh, novel cards with cover + chapter count + last-read badge.
4. **ChapterListScreen** — paginated chapters, "Continue Reading" section, DownloadButton per chapter, play button.
5. **ReaderScreen** — scrollable paragraph list, active paragraph highlight, auto-scroll to active, tap-to-play, settings modal (font size, theme, speed, voices), prev/next chapter buttons in header.
6. **DownloadsScreen** — list of downloaded chapters grouped by novel, progress bars, play/delete actions, pull to refresh.
7. **ProfileScreen** — user header, reading progress list, stats (novels started, chapters read), logout.

### Components

- **DownloadButton** — stateful, shows idle/downloading/completed/failed.
- **GlobalMiniPlayer** — persistent bar at bottom of shell, draggable, play/pause/next/prev + settings modal.
- **PlayPauseFab** — in-screen play control.

## 9. Theming

Material 3 with custom `ColorScheme`:

```dart
const primary = Color(0xFF0EA5E9);
const accent  = Color(0xFFF97316);
const bgDark  = Color(0xFF17171F);
const surfaceDark = Color(0xFF2A2A2A);
const textDark = Color(0xFFF5F5FA);
```

Typography scale matches RN theme (xs 12 → 6xl 48). Border radius: `0, 4, 8, 12, 16, 24, 9999`. Elevation/shadow presets match RN levels.

## 10. Android Widget

`home_widget` package. Render from native (XML RemoteViews on Android) driven by Dart data.

### State keys (SharedPreferences, same prefs namespace as widget)
- `widget_novel_title`
- `widget_chapter_title`
- `widget_paragraph_text`
- `widget_is_playing`
- `widget_speed`
- `widget_cover_path` (pre-cached image file path)

### Actions
- `TOGGLE_PLAY` → calls into Flutter via `HomeWidget.registerBackgroundCallback` → `audioHandler.toggle()`
- `CHANGE_SPEED` → cycle `[0.75, 1.0, 1.25, 1.5, 1.75, 2.0]`
- `NEXT_PARAGRAPH` / `PREV_PARAGRAPH` — if app not running, queue a pending action via SharedPreferences; app drains on next launch.
- `OPEN_APP` → deep link `audiobookreader://widget?action=open`

Debounce updates 300ms, hash-based dedup (same logic as RN).

## 11. Voice Catalog

Hardcoded list (user-selectable):
- en-US-AvaMultilingualNeural (default narrator)
- en-US-ChristopherNeural
- en-US-JennyNeural
- en-GB-SoniaNeural
- en-GB-RyanNeural (default dialogue)
- en-US-AndrewMultilingualNeural
- en-US-EmmaMultilingualNeural

Changing either voice → clear audio cache (memory + disk TTS temp files).

## 12. App Lifecycle

| Event | Action |
|-------|--------|
| `AppLifecycleState.paused` | Preload 15 paragraphs ahead, persist progress. |
| `AppLifecycleState.resumed` | Re-sync playback speed from `just_audio`, consume pending widget action. |
| `didChangeAppLifecycleState` | Route through `WidgetsBindingObserver` on a root widget. |
| Deep link | `audiobookreader://widget?action=next|prev` → `audioHandler.skipToNext/Previous`. |

## 13. Error Handling & UX

- Network failure on login → demo mode path.
- TTS failure → show paragraph-level retry icon in ReaderScreen.
- Download failure → persist `error` status, keep partial files for resume.
- Storage quota check before starting a download.
- Progress save failures are silent (non-blocking).

## 14. File / Folder Layout (target)

```
lib/
├── main.dart
├── app.dart                          (MaterialApp + router)
├── router.dart
├── theme/
│   └── app_theme.dart
├── models/
│   ├── novel.dart
│   ├── chapter.dart
│   ├── chapter_content.dart
│   ├── user_progress.dart
│   ├── downloaded_chapter.dart
│   └── paragraph_audio.dart
├── services/
│   ├── api_client.dart               (dio base)
│   ├── novel_api.dart
│   ├── chapter_api.dart
│   ├── tts_api.dart
│   ├── user_api.dart
│   ├── download_api.dart
│   ├── audio_handler.dart            (AudioHandler subclass)
│   ├── audio_cache_manager.dart
│   ├── offline_content_service.dart
│   ├── download_service.dart
│   ├── download_validator.dart
│   └── storage.dart                  (SharedPreferences wrapper)
├── providers/
│   ├── audio_providers.dart
│   ├── auth_providers.dart
│   ├── download_providers.dart
│   ├── progress_providers.dart
│   └── voice_providers.dart
├── screens/
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── novel_list_screen.dart
│   ├── chapter_list_screen.dart
│   ├── reader_screen.dart
│   ├── downloads_screen.dart
│   └── profile_screen.dart
├── widgets/
│   ├── novel_card.dart
│   ├── chapter_tile.dart
│   ├── paragraph_item.dart
│   ├── download_button.dart
│   ├── global_mini_player.dart
│   └── voice_picker_modal.dart
└── widget/
    └── audiobook_home_widget.dart    (home_widget bridge)

android/
└── app/src/main/
    ├── res/layout/widget_layout.xml
    ├── res/xml/widget_info.xml
    └── java/.../AudiobookWidgetProvider.kt
```

## 15. What we're explicitly NOT porting

- RNTP patches (`patches/react-native-track-player+4.1.2.patch`)
- The polling progress fallback (500ms) — `just_audio` fires `playerStateStream` reliably.
- The `operationLock` / `suppressPauseEvents` / `completionHandled` flags — these existed to compensate for RNTP's unreliable events under New Architecture. just_audio doesn't need them.
- The `GlobalAudioState` singleton — Riverpod provides equivalent cross-isolate access via `ProviderContainer`.

## 16. Success Criteria

A Flutter rewrite is "better" than the current RN app if:
1. Notification Play/Pause/Next/Previous all work reliably.
2. Auto-advance fires exactly once per paragraph (no missed / duplicate triggers).
3. Offline-downloaded chapters play without hitting the network.
4. Paragraph audio preloads within the character/distance budget.
5. Playback speed changes take effect within 200ms without restarting the track.
6. Widget controls work when the app is backgrounded.
7. State survives app kill (current chapter/paragraph restores on next launch if audio was playing).
