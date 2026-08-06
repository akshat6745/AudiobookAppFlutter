# Change Log (AI-maintained)

Append dated entries when making significant changes. Keep entries terse.

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
