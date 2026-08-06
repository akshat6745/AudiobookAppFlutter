# Change Log (AI-maintained)

Append dated entries when making significant changes. Keep entries terse.

---

## 2026-08-07 — Playback overhaul: session-scoped cache, voice UX, perf, error handling

**Bug fix — chapter-switch audio leak (root cause: unscoped cache + no session identity):**
- `audio_cache_manager.dart`: cache keys changed from bare `int` paragraph index to
  `(novelSlug, chapterNumber, paragraphIndex)` — same index across two chapters can no
  longer collide. Added a `_generation` counter bumped synchronously by `setContext`
  (chapter switch), `updateVoices`, `updateEngine`; every async internal
  (`_loadAudioForParagraph`, `_loadInternal`, `_pumpPreload`) captures `gen` on entry and
  discards its result if the generation has since moved on. In-flight `_activeRequests`
  completers are failed with `_StaleSessionException` on session change so awaiters bail
  instead of hanging. Preload timer is now stored/cancelled on every session change
  (previously never cancelled).
- `audio_handler.dart`: added its own `_generation`, bumped by `setParagraphs` (new
  chapter) and `stop()`. `playParagraph` re-checks `gen == _generation && paragraphIndex
  == _currentIndex` after every `await` before touching `_player` — a stale auto-advance
  or superseded tap can no longer call `setAudioSource`/`play`.
- `playback_coordinator.dart`: `loadChapter` now calls `_handler.pause()` and resets
  handler index state before any async content resolution, making the reset atomic.
- Regression tests added: `test/audio_cache_preload_test.dart` → `chapter switch —
  session safety` group (5 cases covering leak, stale preload, text-mismatch cache hit,
  in-flight cancellation, cross-chapter same-index independence).

**Voice selection UX:**
- `kokoro_voices.dart` trimmed from 53 to the 28 English voices that actually exist in
  the installed `kokoro-en-v0_19` model (sids 28–52 belonged to a different, uninstalled
  multi-language model and would have misbehaved).
- Added `voice_preferences_provider.dart`: `favoriteVoiceIdsProvider` (seeded
  am_eric/am_michael/af_heart, toggle + reorder) and `recentVoiceIdsProvider` (capped at
  6, `markUsed` dedupes+pushes-to-front). Both SharedPrefs-backed with a `ready` Future
  for tests.
- `voice_picker.dart` rewritten as `ConsumerStatefulWidget`: search, gender/accent filter
  chips, favorites section (reorderable), recents section, per-voice sample playback
  (dedicated preview `AudioPlayer`, samples cached to temp dir).
- `now_playing_modal.dart`: added a "Quick presets" row wiring `KokoroVoices.presets`.
- `main.dart`: narrator/dialogue voice selections now persist to `SharedPreferences` and
  restore on app start (previously in-memory only, reset every launch).

**Performance:**
- `.select()` narrowing added for `audioStateProvider`/`progressProvider`/
  `downloadsProvider` watches in `reader_screen.dart` / `chapter_list_screen.dart` that
  were still watching whole objects.
- `global_mini_player.dart`: short-circuits to `SizedBox.shrink()` via
  `ModalRoute.isCurrent` when its route isn't the visible one — it's intentionally
  mounted in 3 places (shell + reader + chapter list) but only the visible one now
  subscribes/rebuilds.
- `reader_screen.dart`: `_itemKeys` (`GlobalKey` per paragraph) is now pruned to ~80
  entries around the active viewport instead of growing unbounded per chapter.
- `novel_list_screen.dart`: `CachedNetworkImage` covers now set `memCacheWidth`/
  `memCacheHeight` to the displayed size × device pixel ratio.

**Error handling:**
- `tts/remote_tts_engine.dart`: added a `connectivity_plus` gate — `isAvailable()`
  reflects real reachability, and `synthParagraph()` throws `TtsOfflineException`
  immediately when offline instead of waiting out a dio connect timeout.
- `audio_handler.dart`: wired `audio_session`'s `interruptionEventStream` (duck → lower
  volume and restore; pause/unknown → pause and resume only if *we* paused for it) and
  `becomingNoisyEventStream` (headphones unplugged → pause immediately).
- `audio_cache_manager.dart`: freshly-synthesized TTS output is now size-checked
  (>1024 bytes) before being marked `audioReceived = true`, mirroring the existing
  offline-file validation — a truncated/corrupt synth result fails instead of getting
  cached and played.

**Code quality / cleanup:**
- Removed dead no-ops `AudioCacheManager.setCurrentlyPlaying` / `setPlaybackSpeed` and
  their call sites in `audio_handler.dart` (preload buffer is character-based and was
  already independent of both).
- Removed unused `AudioCacheConfig.cacheExpiry` (never read; generation-based
  invalidation already covers correctness, window-based eviction already covers memory).
- `tts_model_manager.dart`: `_isComplete()` now also checks `voices.bin` (previously a
  model missing the speaker-embedding file could be adopted as "complete" and fail at
  synthesis time instead of at install time).
- `lib/services/tts/README.md` rewritten — no longer describes the engine as an
  unimplemented "Scaffold"; documents the actual wiring and provisioning flow.
- Added `TTS_ENGINE_RECOMMENDATION.md` — formal write-up confirming Kokoro/`sherpa_onnx`
  as the on-device engine (already implemented; this is documentation only).

---

## 2026-05-17 — Performance & loading state pass

**Performance (rebuild narrowing):**
- `reader_screen.dart`: `ref.watch(audioStateProvider)` → `.select((s) => (activeIndex, isThisChapter))` — excludes `isPlaying`/`isLoading`/`content`/`playbackSpeed` from triggering rebuilds. `downloadsProvider` → `.select(...)` deriving only `downloaded`/`downloading` booleans for this chapter.
- `chapter_list_screen.dart`: `progressProvider` and `lastPositionProvider` → `.select((m) => m[novel.slug])` — no longer rebuilds on other novels' changes.
- `global_mini_player.dart`: `audioHandlerProvider` → `ref.read` (singleton, never changes). `audioStateProvider` → `.select((s) => (currentIndex, content, chapter, novel))` — excludes `isPlaying`/`isLoading`.
- `novel_list_screen.dart`: Deduplicated `ref.watch(authProvider)` — single `user` local variable.

**Loading states:**
- `novel_list_screen.dart` (`_NovelCard`): `CachedNetworkImage` now shows a `CircularProgressIndicator` placeholder while the cover loads (was pop-in with no placeholder).
- `login_screen.dart`: `_submit()` wrapped in try/finally — `_submitting` always resets if an unexpected exception escapes (previously stayed `true` on unexpected throw).

**Bug fixes:**
- `audio_cache_manager.dart`: `_triggerPreload` now cancels the previous `_preloadTimer` before scheduling a new one — prevents overlapping preload work on rapid paragraph changes.
- `audio_cache_manager.dart`: `clearCache()` now cancels and nulls `_preloadTimer` before clearing the cache — previously a pending timer could fire after `clearCache` (e.g., on voice change) and re-populate the cache with stale paragraphs at incorrect indices using the new voices.

**Removed:**
- `reader_screen.dart`: Removed now-unused `_findDownload` method (download lookup moved into `downloadsProvider.select` closure).
