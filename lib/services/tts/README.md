# TTS engine seam

This folder holds the pluggable TTS layer described in
[`OFFLINE_FIRST_ARCHITECTURE.md`](../../../OFFLINE_FIRST_ARCHITECTURE.md) §4.
Playback/caching code depends only on `TtsEngine`, so online vs. on-device is a
swap, not a rewrite.

| File | Role |
|------|------|
| `tts_engine.dart` | `TtsEngine` interface + `TtsAudio` (bytes + `'mp3'`/`'wav'`) |
| `remote_tts_engine.dart` | Online — wraps existing `TtsApi` → backend `/tts-dual-voice` (MP3), connectivity-gated (fails fast with `TtsOfflineException` when offline instead of waiting out a network timeout) |
| `sherpa_onnx_tts_engine.dart` | **On-device** — Kokoro ONNX via `sherpa_onnx`, fully offline (WAV), generation runs in a dedicated background isolate |
| `tts_model_manager.dart` | Downloads/extracts/locates the Kokoro model archive on-device |
| `kokoro_voices.dart` | Voice catalog (trimmed to the 28 voices in the installed `kokoro-en-v0_19` model) + curated presets |
| `dual_voice_segmenter.dart` | Narrator/dialogue split, ported from `app/api/tts.py` |
| `wav_encoder.dart` | PCM16 → WAV container encoding for on-device output |
| `../../providers/tts_engine_provider.dart` | Riverpod selector: on-device when a model is installed, else remote |

## Status

Implemented and wired end-to-end, not a scaffold. `AudioCacheManager` calls
`TtsEngine.synthParagraph()` through `activeTtsEngineProvider` for every
paragraph that isn't already covered by offline-downloaded audio; the engine
in use is swappable at runtime via `AudioCacheManager.updateEngine()` (voice
picker → on-device model download flow). See
[`TTS_ENGINE_RECOMMENDATION.md`](../../../TTS_ENGINE_RECOMMENDATION.md) for
why Kokoro/`sherpa_onnx` was chosen as the on-device engine.

## Provisioning the on-device model

Handled automatically by [`TtsModelManager`](tts_model_manager.dart) +
[`tts_model_download_provider.dart`](../../providers/tts_model_download_provider.dart)
and surfaced in the UI via
[`tts_model_download_tile.dart`](../../widgets/tts_model_download_tile.dart):

1. User opts in from the voice picker / settings.
2. `TtsModelManager.downloadAndInstall()` fetches the Kokoro
   `kokoro-en-v0_19.tar.bz2` release asset, extracts it into
   `<app documents>/models/kokoro/` in a background isolate, and remembers the
   resolved path in `SharedPreferences`.
3. Once `TtsModelManager.installedPaths()` resolves (requires `model.onnx`,
   `voices.bin`, `tokens.txt`, and `espeak-ng-data/` to all be present),
   `activeTtsEngineProvider` returns `SherpaOnnxTtsEngine` automatically —
   no other code needs to know which engine is active.

## Notes

- On-device output is **WAV**; `just_audio` plays it natively (no MP3 encoder
  needed on device). Remote output is **MP3**.
- Dual-voice: Kokoro uses `narratorSid`/`dialogueSid` speaker ids within one
  model — no second model needed (unlike e.g. Piper).
- `AudioCacheManager` clears cached audio when the engine *kind* changes
  (remote ↔ on-device), since the cached format differs — see
  `updateEngine()`.
