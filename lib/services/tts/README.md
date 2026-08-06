# TTS engine seam — POC runbook

This folder holds the pluggable TTS layer described in
[`OFFLINE_FIRST_ARCHITECTURE.md`](../../../OFFLINE_FIRST_ARCHITECTURE.md) §4.
Playback/caching code depends only on `TtsEngine`, so online vs. on-device is a
swap, not a rewrite.

| File | Role |
|------|------|
| `tts_engine.dart` | `TtsEngine` interface + `TtsAudio` (bytes + `'mp3'`/`'wav'`) |
| `remote_tts_engine.dart` | Online — wraps existing `TtsApi` → backend `/tts-dual-voice` (MP3) |
| `sherpa_onnx_tts_engine.dart` | **On-device** — Piper/Kokoro ONNX via `sherpa_onnx`, offline (WAV) |
| `dual_voice_segmenter.dart` | Narrator/dialogue split, ported from `app/api/tts.py` |
| `../../providers/tts_engine_provider.dart` | Riverpod selector: on-device when a model is installed, else remote |

## Status
Scaffold. The `sherpa_onnx` import resolves only after the dependency is
installed, and the on-device engine's exact API params should be confirmed
against the installed package version's example.

## Bring the POC up (Part A of OFFLINE_TTS_POC_PLAN.md)

1. **Install the dependency**
   ```bash
   flutter pub get          # or: flutter pub add sherpa_onnx
   flutter analyze          # expect this folder clean after pub get
   ```

2. **Provision a model** (POC: side-load into the app documents dir)
   - Kokoro (multi-voice; best for dual-voice): `model.onnx`, `voices.bin`,
     `tokens.txt`, `espeak-ng-data/` — laid out as in `TtsModelPaths`.
   - Or a Piper `en_US` voice for the light/fast comparison.

3. **Point the app at the model**
   Override `ttsModelPathsProvider` to return a `TtsModelPaths(<dir>)`
   (e.g. `<app documents>/models/kokoro`). Once `isAvailable()` is true,
   `activeTtsEngineProvider` returns the on-device engine automatically.

4. **Generate offline & measure**
   Feed real chapter paragraphs (from `downloads/<id>/content.json`),
   write the resulting `.wav` into the same `downloads/<id>/` layout, and run
   the browse→read→listen flow in **airplane mode**. Record latency, RTF,
   size, memory, battery/thermal per the plan's tables.

## Notes
- On-device output is **WAV**; `just_audio` plays it natively (no MP3 encoder
  needed on device).
- Dual-voice: Kokoro uses `narratorSid`/`dialogueSid` in one model; Piper needs
  two models (more RAM) — see the plan's decision rubric.
