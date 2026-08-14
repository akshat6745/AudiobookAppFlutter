# Can Kokoro do emotional/expressive TTS? (analysis)

**Date:** 2026-08-14
**Context:** Investigated whether the app's on-device Kokoro engine (via
`sherpa_onnx`) can be driven with "emotional points" to simulate a voice with
emotional depth — e.g. matching what Qwen3-TTS/Chatterbox/EmotiVoice offer
(see `.claude`-adjacent research below on those alternatives).

## Verdict: no, not through the current binding

Checked the actual control surface exposed by the installed `sherpa_onnx`
Flutter package (`~/.pub-cache/hosted/pub.dev/sherpa_onnx-1.13.3/lib/src/tts.dart`):

```dart
class OfflineTtsGenerationConfig {
  const OfflineTtsGenerationConfig({
    this.silenceScale = 0.2,
    this.speed = 1.0,
    this.sid = 0,
    this.referenceAudio,       // only used by other model families (e.g. ZipVoice cloning)
    this.referenceSampleRate = 0,
    this.referenceText = '',
    this.numSteps = 5,         // only used by diffusion-style models, not Kokoro
    this.extra = const {},
  });
}
```

For **Kokoro specifically**, the only real knobs are:
- `sid` — which of the ~28 preset English voices (fixed timbre/personality per id)
- `speed` — playback rate (via `lengthScale` in the model, not naive resampling)
- `silenceScale` — pause length between segments

There is **no pitch parameter and no emotion/style vector** exposed. Kokoro's
underlying StyleTTS2 architecture does have an internal style vector, but it's
baked in fixed per voice at ONNX export time — this binding gives no way to
interpolate or drive it with a parameter. Getting real control there would
require re-exporting the model with the style vector as an explicit input and
writing new native bindings — comparable effort to adopting a whole new model,
not a config change.

## What's a fake-checked alternative to "PowerPoint the emotion" checked

`OfflineTtsModelConfig` in the same package also supports `vits`, `matcha`,
`kitten`, `zipvoice`, `pocket`, `supertonic` — none of these are Qwen3-TTS,
Chatterbox, or EmotiVoice either (those need custom bindings, out of scope;
see chat history around 2026-08-14 for the full write-up on why on-device
Qwen3-TTS/Chatterbox/EmotiVoice were rejected, and why backend-hosting them
would need GPU infra AudioBookPython doesn't have today).

## What IS achievable today with zero new native engineering

1. **Per-segment speed/pause heuristics** — extend `DualVoiceSegmenter`
   (already splits narration from dialogue) to also vary `speed`/`silenceScale`
   per segment based on punctuation/lexical cues (exclamations → faster/less
   silence, ellipses → slower/more silence). Real, cheap, but it's *pacing*,
   not tone.
2. **Per-character voice selection from the ~28 Kokoro voices** — different
   voices already have distinct innate timbre (brighter/younger vs.
   deeper/calmer). Could pick voices per character/mood rather than one fixed
   narrator+dialogue pair. Still discrete voice-switching, not modulation of
   a single voice's emotion.

Neither is implemented yet (parked — user said "not now, just wanted the
research" as of 2026-08-14). Revisit this file before spending more time on
"emotional Kokoro" — the constraint is structural (binding + export), not a
tuning problem.
