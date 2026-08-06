# Offline-First Architecture — Native Piper/Kokoro TTS

**Status:** Design (approved direction, pre-implementation)
**Scope:** `audiobook-app-flutter` (client) + `AudioBookPython` (backend)
**Goal:** The app is fully usable with **zero internet** — browse the library, open any chapter, read its text, and **listen to high-quality generated speech entirely on-device (Android / iOS / laptop)**. Cloud (Cloudflare D1/R2) becomes an optional sync + backup layer that never blocks playback.

---

## 1. Decisions (locked)

| # | Decision | Choice |
|---|----------|--------|
| 1 | On-device TTS | **`sherpa_onnx`** runs **Kokoro** (chosen) ONNX **natively, offline** — Piper kept only as a low-end-device fallback. No phone-side Python. |
| 2 | Server-side TTS | **Replace `edge-tts`** in the Python backend with the **same** Piper/Kokoro models → identical voices on device and the deployed website. |
| 3 | Local metadata store | Add **SQLite** (`drift`) to the Flutter app, mirroring `sql/d1_schema.sql`. |
| 4 | Sync | **Offline-first**: local is source of truth; opportunistic push/pull to D1/R2; **furthest-progress-wins** conflict resolution. |
| 5 | Offline auth | Cached session via existing `flutter_secure_storage`; valid until next successful online check. |
| 6 | Model delivery | Decided in the POC (bundle-in-app vs download-on-first-run). Default lean: **download-on-first-run**. |

Why `sherpa_onnx` and not on-device Python: Piper and Kokoro are **ONNX** models. `sherpa_onnx` (C++ engine with Dart bindings) runs both offline on Android/iOS/macOS/Windows/Linux and bundles the espeak-ng phonemizer. It gives the exact high-quality voices with **no** Python runtime on the device, in the single Flutter bundle. Embedding Python (Chaquopy) would be heavier, Android-mostly, and offer no quality gain over the same ONNX model.

---

## 2. Current state (how audio flows today)

```
Flutter app                          Python backend (cloud)
-----------                          ----------------------
tts_api.dart ──POST /tts-dual-voice──► app/api/tts.py
  {text, paragraphVoice,               edge_tts.Communicate(...)  ── Microsoft cloud TTS
   dialogueVoice}                       (websocket, REQUIRES INTERNET)
        ◄──────── MP3 bytes ──────────
audio_cache_manager.dart  → cache
just_audio + audio_service → playback
```

- **Everything audio is server-side and online.** The phone generates nothing locally.
- **Offline downloads already exist** (`download_service.dart`, `offline_content_service.dart`): a chapter is stored as `downloads/<downloadId>/content.json` (`paragraphs[]`, `chapter_title`) plus per-paragraph `0.mp3 … N.mp3` and `title.mp3`. Playback **already falls back to live TTS for any missing paragraph** — this is the natural hook for on-device generation.
- **Metadata** lives in `SharedPreferences` JSON blobs (`StorageKeys.downloadedChapters`, voice prefs). **No SQLite.**
- **Auth tokens** already use `flutter_secure_storage` (good — matches secret-handling guidance).
- **Backend data model** (`sql/d1_schema.sql`): `novels`, `chapters` (metadata only; text in R2 as `.txt.gz`, audio path in `r2_audio_path`), `users` (bcrypt), `user_progress` (`chapter_number` + `audio_position`, `UNIQUE(user_id, novel_id)`, `updated_at`).

---

## 3. Target architecture

```
┌─────────────────────────── Flutter app (single bundle) ───────────────────────────┐
│                                                                                     │
│  Reader / Player UI                                                                 │
│        │                                                                            │
│        ▼                                                                            │
│  TtsEngine (interface)                                                              │
│    ├── RemoteTtsEngine   → POST /tts-dual-voice (online, existing behavior)         │
│    └── SherpaOnnxTtsEngine → Piper/Kokoro ONNX, ON-DEVICE, OFFLINE  ◄── NEW         │
│        │        ▲                                                                   │
│        ▼        │ dual-voice split (DualVoiceSegmenter, ported from tts.py)         │
│  audio_cache_manager  → LocalStore (SQLite/drift) + files under downloads/<id>/     │
│        │                                                                            │
│        ▼                                                                            │
│  just_audio + audio_service (unchanged)                                             │
│                                                                                     │
│  SyncService  ──(when online)──►  Cloudflare D1 / R2 via dio                        │
└─────────────────────────────────────────────────────────────────────────────────┘
                                          ▲
                                          │ same ONNX models
┌──────────────────────── Python backend (unchanged role) ──────────────────────────┐
│  app/api/tts.py: edge-tts  ──►  Piper/Kokoro ONNX (sherpa-onnx / piper) ◄── CHANGE  │
│  Serves the deployed website + optional pre-generated audio to R2                   │
│  D1/R2 remain the cloud sync/backup target                                          │
└─────────────────────────────────────────────────────────────────────────────────┘
```

The **REST contract is unchanged** — the deployed website keeps working. "Offline" is an on-device capability added to the app; the backend simply swaps *how* it synthesizes audio.

---

## 4. Decision 1 — On-device TTS (`sherpa_onnx`)

### 4.1 The seam
Introduce a `TtsEngine` interface so on-device and remote generation are interchangeable, and the existing `tts_api.dart` becomes one implementation:

```dart
// lib/services/tts/tts_engine.dart
abstract class TtsEngine {
  /// Produce audio bytes for a single paragraph, dual-voice.
  Future<Uint8List> synthParagraph({
    required String text,
    required String paragraphVoice,
    required String dialogueVoice,
  });
}

// RemoteTtsEngine  → wraps existing TtsApi.convertDualVoice (online)
// SherpaOnnxTtsEngine → offline, native Piper/Kokoro
```

A provider (Riverpod, alongside the existing `backend_provider.dart`) selects the engine: **on-device by default when a model is installed; remote as an online fallback / for parity with the website.**

### 4.2 sherpa_onnx specifics
- Package: `sherpa_onnx` (pub.dev) — `OfflineTts` API, VITS (Piper) + Kokoro support, cross-platform.
- **Output is WAV/PCM** (Float32 samples at the model's sample rate), not MP3. `just_audio` plays WAV natively, so the **offline cache format becomes `.wav`** (slightly larger than MP3 — acceptable for a local cache; quantify in POC). No MP3 encoder needed on-device.
- Model assets per Piper voice: `model.onnx` + `tokens.txt` + `espeak-ng-data/` (+ config). Kokoro ships a single multi-voice model + `voices.bin` + tokens.

### 4.3 Dual-voice on-device
`tts.py`'s `text_to_speech_dual_voice` splits text on curly quotes (`“ … ”` → dialogue voice; the rest → narrator voice). Port that segmentation to a Dart `DualVoiceSegmenter` (also carry over the asterisk/spam-line cleanup) so on-device audio matches server output.

- **Kokoro (chosen)** — multi-speaker, one model, many `sid`s: the natural fit for dual-voice → pick narrator `sid` and dialogue `sid` from one model. The `SherpaOnnxTtsEngine` scaffold is already wired to `OfflineTtsKokoroModelConfig`.
- **Piper** is single-speaker per model → dual-voice means loading two Piper models (more memory) *or* accepting a single narrator voice offline. Captured as a POC trade-off.

### 4.4 Cache & reuse
On-device generation writes into the **existing** `downloads/<id>/` layout (`<paragraphIndex>.wav`, `title.wav`) via `audio_cache_manager` / `offline_content_service`, so:
- Any chapter listened to once is available offline afterward, no code changes to playback.
- The existing "missing paragraph → fall back to live TTS" path becomes "missing paragraph → generate on-device," which also works with zero internet.

---

## 5. Decision 2 — Server-side edge-tts → Piper/Kokoro

Replace `edge_tts` in `app/api/tts.py` with the **same** Piper/Kokoro models so device and website voices are identical.

**Preferred: native Python library, no shell.** Use `sherpa-onnx` (Python) or a Piper Python binding to synthesize in-process. This aligns with the OX guideline ("prefer Python native libraries over shell commands") and avoids subprocess entirely.

**If a CLI (e.g. `piper`) is used instead**, apply the command-injection-safe pattern — text via **stdin**, model path from **internal allowlisted config** (never user input), list args, `shell=False`, timeout:

```python
# Voice name → model path is internal config, NOT user-controlled.
VOICE_MODELS = {"narrator": "/models/en_US-narrator.onnx",
                "dialogue": "/models/en_US-dialogue.onnx"}

def synth(text: str, voice: str) -> bytes:
    model = VOICE_MODELS.get(voice)          # allowlist lookup
    if model is None:
        raise ValueError("Unknown voice")
    result = subprocess.run(
        ["piper", "--model", model, "--output_file", "-"],
        input=text.encode(),                 # user text via stdin, never the shell
        capture_output=True, shell=False, timeout=60,
    )
    return result.stdout
```

The dual-voice segmentation and concurrency cap (`_TTS_SEMAPHORE`) in `tts.py` stay; only the per-segment synthesizer changes. Pre-generated MP3s can still be pushed to R2 (`r2_audio_path`) for the online download path.

---

## 6. Decision 3 — Local metadata store (SQLite / `drift`)

Add `drift` (SQLite) to the app, mirroring `sql/d1_schema.sql`, replacing the `SharedPreferences` JSON blobs for structured data:

| Local table | Mirrors D1 | Notes |
|-------------|-----------|-------|
| `novels` | `novels` | + `synced_at` |
| `chapters` | `chapters` | + local `content_path`, `audio_dir` |
| `user_progress` | `user_progress` | + `dirty` flag, `updated_at` for sync |
| `downloaded_chapters` | (app-only) | migrate from the current JSON blob |

- Chapter **text** and **audio** stay on the filesystem (`downloads/<id>/`); SQLite holds the index/metadata and sync bookkeeping.
- Keep `flutter_secure_storage` for tokens; keep `SharedPreferences` for simple prefs (voice, speed) — no need to migrate those.

---

## 7. Decision 4 — Offline-first sync

**Local is the source of truth.** Writes hit SQLite/disk first and never block on the network.

- **Push:** rows marked `dirty` are sent to D1 when connectivity returns (`connectivity_plus`); clear `dirty` on ack.
- **Pull:** on reconnect / app open, fetch remote rows changed since `last_sync_at`; merge into local.
- **Conflict resolution — reading progress:** the meaningful field is how far the user got.
  - `chapter_number`: **max wins**.
  - `audio_position` within the same `chapter_number`: **max wins** ("furthest-progress-wins").
  - Everything else: **last-write-wins** by `updated_at`.
  This avoids a later device on an earlier chapter clobbering real progress.
- **Content/audio:** additive; never deleted by sync. R2 is backup; local files are authoritative for playback.

---

## 8. Decision 5 — Offline auth

- Cache the session/identity in `flutter_secure_storage` (already in use).
- Offline, treat the cached session as **valid until the next successful online check**; the whole library + playback work without re-auth.
- Re-validate on reconnect; only then refresh/expire tokens.
- **Security:** never log tokens; never return exception details/stack traces to the client (backend returns generic errors, logs server-side). Passwords stay bcrypt (already true in `users` schema).

---

## 9. Decision 6 — Model delivery

| Option | APK/IPA impact | UX | Recommendation |
|--------|----------------|----|----------------|
| Bundle model in app | Piper +60–90 MB, Kokoro +300 MB | Works instantly, no download | Only if size acceptable |
| **Download on first run** | Small binary | One-time download + progress UI, then fully offline | **Default lean** — pin in POC |

If downloaded: store under app documents, verify checksum, allow re-download if corrupt (mirror the existing audio repair pattern in `download_service.dart`).

---

## 10. What changes where (implementation map)

**Flutter (`audiobook-app-flutter`)**
- `pubspec.yaml`: add `sherpa_onnx`, `drift` + `sqlite3_flutter_libs`, `connectivity_plus`, `crypto` (checksums).
- `lib/services/tts/` (new): `tts_engine.dart`, `sherpa_onnx_tts_engine.dart`, `remote_tts_engine.dart`, `dual_voice_segmenter.dart`.
- `lib/services/tts_api.dart`: keep as `RemoteTtsEngine`'s transport.
- `lib/services/db/` (new): drift schema + DAOs mirroring D1.
- `lib/services/sync_service.dart` (new): push/pull + conflict resolution.
- `audio_cache_manager.dart` / `offline_content_service.dart`: write/read `.wav` from on-device generation into the existing `downloads/<id>/` layout.
- `providers/`: engine selection + sync providers.

**Python (`AudioBookPython`)**
- `app/api/tts.py`: swap the per-segment synthesizer edge-tts → Piper/Kokoro (native lib preferred). Keep segmentation + semaphore.
- `requirements.txt`: add `sherpa-onnx` (or piper binding); optionally drop `edge-tts` later.
- Optional: pre-generate + upload MP3 to R2 (`r2_audio_path`).

---

## 11. Security considerations (this change)

- **Command injection (backend):** prefer the native Python library (no subprocess). If a CLI is unavoidable, use the list-args / stdin / `shell=False` / timeout pattern in §5; voice→model is an internal allowlist, user text never reaches the shell.
- **Secrets:** tokens in `flutter_secure_storage`; CF/R2 credentials stay in backend env (`app/core/settings.py`) — never shipped to the client.
- **Error exposure:** backend logs full errors server-side, returns generic messages (the app must not depend on server stack traces).

---

## 12. Risks & trade-offs

| Risk | Impact | Mitigation |
|------|--------|-----------|
| On-device latency (esp. Kokoro on mid devices) | Slow first play | Generate-ahead N paragraphs; cache; POC benchmarks on OnePlus 15 |
| Model size / app bloat | Install friction | Download-on-first-run |
| WAV cache larger than MP3 | More disk | Acceptable; optionally transcode later |
| Piper single-speaker vs dual-voice | Two models = more RAM | Prefer Kokoro multi-speaker for dual-voice |
| Voice mismatch device vs website | Inconsistent UX | Same ONNX models both sides (Decision 2) |
| Sync conflicts on progress | Lost place | Furthest-progress-wins (§7) |

---

## 13. Success criteria (definition of done)

1. **Airplane mode:** list library, open **any** chapter, see text, hear on-device audio — no errors, no infinite spinners.
2. **Reuse:** a chapter heard once plays from cache offline afterward.
3. **Sync round-trip:** make progress offline → reconnect → D1 reflects the furthest position; no data loss.
4. **Parity:** device voice == website voice (same models).

**Verification:** disabled-networking manual run of browse→read→listen; offline-progress → reconnect → inspect D1 row.

---

## 14. Follow-ups / open items

- Which specific Piper voices + whether Kokoro is worth its size → **POC** (`OFFLINE_TTS_POC_PLAN.md`).
- Bundle vs download → **POC**.
- Whether to fully retire `edge-tts` or keep as a fallback.
- Optional pointer doc in `AudioBookPython` referencing §5.
