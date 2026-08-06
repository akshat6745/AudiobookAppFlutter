# On-Device TTS Engine Recommendation

**Status: decided and implemented.** This formalizes the choice already made and
shipped in [`lib/services/tts/sherpa_onnx_tts_engine.dart`](lib/services/tts/sherpa_onnx_tts_engine.dart) —
no further engineering is proposed here, this is the write-up called for by the
audit's Part 8.

## Recommendation

**Kokoro, via the `sherpa_onnx` Dart/Flutter binding**, as the on-device TTS
engine, with the existing backend `edge-tts` remote path (`RemoteTtsEngine`)
kept as the online fallback when no model is installed or the device is
low-end. This is what `activeTtsEngineProvider` already selects.

## Candidates considered

| Engine | Verdict | Why |
|---|---|---|
| **Kokoro (via `sherpa_onnx`)** | **Chosen** | Single multi-speaker ONNX model — narrator/dialogue are just two speaker ids (`sid`) in one loaded model, which is exactly what dual-voice narration needs without doubling memory. Runs natively on Android/iOS/macOS/Windows/Linux through one Dart binding, no phone-side Python. Apache-2.0-licensed weights. Meets real-time-factor targets on flagship hardware (RTF ≈ 0.65–0.75 with 4 ONNX intra-op threads on Snapdragon 8 Elite class devices — comfortably faster than real-time; see `numThreads` tuning note in `sherpa_onnx_tts_engine.dart`). |
| **Piper (via `sherpa_onnx`)** | Fallback only | Same runtime (`sherpa_onnx`), so it's a cheap hedge, not a separate integration. But Piper models are single-speaker — dual-voice narration would require loading *two* Piper models simultaneously (roughly double the resident memory of one Kokoro model) or degrading to a single narrator voice offline. Kept as the low-end-device fallback path in the architecture doc, not wired as a default. |
| **Coqui XTTS** | Rejected | Designed for voice-cloning quality via a much larger transformer-based decoder; multi-hundred-MB-to-GB model footprint and RTF well above 1.0 on mobile CPUs without a dedicated accelerator. Appropriate for a server-side cloning feature, not a phone-resident narrator. |
| **StyleTTS2** | Rejected | Highest natural-speech quality of the options surveyed, but is a research-grade PyTorch model with no mature, maintained mobile/ONNX runtime at the time of evaluation — would mean owning a custom export + mobile inference pipeline instead of consuming a supported package. Not worth the maintenance cost for a marginal quality gain over Kokoro for narrated prose. |
| **MeloTTS** | Rejected | Reasonable quality/size trade-off, but single-speaker-per-language checkpoints (like Piper) reintroduce the dual-voice-needs-two-models problem, and it lacks the same breadth of pre-existing Flutter/Dart tooling that `sherpa_onnx` already provides for Kokoro. |

## Why `sherpa_onnx` as the runtime (not raw ONNX Runtime, not embedded Python)

- It's a C++ engine with first-party Dart bindings — one dependency covers
  Android, iOS, macOS, Windows, and Linux, matching this app's cross-platform
  target.
- It bundles the `espeak-ng` phonemizer, so no separate text-normalization
  pipeline is needed on-device.
- Embedding Python (e.g. via Chaquopy) to reuse the backend's Python TTS stack
  would be heavier, effectively Android-only, and offer zero quality upside
  over calling the same ONNX weights through `sherpa_onnx` directly.

## Implementation notes (already in place)

- Generation runs in a **dedicated background isolate**
  (`sherpa_onnx_tts_engine.dart`) — `OfflineTts.generate` is a blocking native
  call; running it on the main isolate froze the UI (ANR) on tap-to-play.
- Output is 16-bit PCM **WAV**, played natively by `just_audio` — no on-device
  MP3 encode step.
- The model (`kokoro-en-v0_19`, ~28 English voices) is **downloaded on first
  opt-in**, not bundled, keeping the store binary small; see
  `TtsModelManager` and the delivery-decision rationale in
  `OFFLINE_TTS_POC_PLAN.md` §4.
- `AudioCacheManager` treats engine identity (remote vs. on-device, and model
  kind) as part of cache invalidation (`updateEngine()`), since MP3 (remote)
  and WAV (on-device) outputs are never interchangeable.

## Fallback behavior

`activeTtsEngineProvider` selects the on-device Kokoro engine only once
`TtsModelManager.installedPaths()` resolves a complete model directory
(`model.onnx`, `voices.bin`, `tokens.txt`, `espeak-ng-data/` all present).
Otherwise it falls back to `RemoteTtsEngine`, which itself now fails fast with
a clear error when there's no network connectivity (see
[`remote_tts_engine.dart`](lib/services/tts/remote_tts_engine.dart)) rather
than hanging on a dio timeout.
