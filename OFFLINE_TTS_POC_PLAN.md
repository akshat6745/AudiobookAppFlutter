# Offline TTS — Proof-of-Concept Plan

**Companion to:** `OFFLINE_FIRST_ARCHITECTURE.md`
**Objective:** De-risk the two open decisions before committing to full implementation:
1. **Which on-device engine/voice** — Piper vs Kokoro (quality, speed, size, battery/heat) on the target device.
2. **Model delivery** — bundle-in-app vs download-on-first-run.

Plus prove the server-side edge-tts → Piper/Kokoro swap so device and website voices match.

**Primary device:** OnePlus 15 (flagship) — but also record numbers on a mid-range Android and desktop for the cross-platform claim.

---

## 1. Scope

**In:** wiring `sherpa_onnx` into the Flutter app behind the `TtsEngine` seam; generating dual-voice audio for a few real chapters fully offline; measuring; a parallel Python bench of the same models.

**Out:** full SQLite/sync layer, UI polish, voice-cloning (Pocket-TTS), retiring edge-tts. Those follow only after the engine choice is made.

---

## 2. Part A — On-device `sherpa_onnx` POC (Flutter)

### Steps
1. Add `sherpa_onnx` to `pubspec.yaml`; confirm it builds for Android (start here) and macOS (laptop parity check).
2. Fetch models to app documents (POC: side-load; production decision in Part C):
   - **Piper**: an `en_US` voice (e.g. a medium-quality model) — `model.onnx` + `tokens.txt` + `espeak-ng-data/`.
   - **Kokoro**: the multi-voice English model + `voices.bin` + tokens.
3. Implement `SherpaOnnxTtsEngine` behind the `TtsEngine` interface (see architecture §4.1). Output `.wav`.
4. Port `DualVoiceSegmenter` from `app/api/tts.py` (curly-quote split → dialogue voice; rest → narrator; carry the asterisk/spam cleanup).
   - Kokoro: narrator `sid` vs dialogue `sid` in one model.
   - Piper: two models (or single narrator voice) — record the RAM cost.
5. Generate audio for **3 real chapters** (reuse `downloads/<id>/content.json` `paragraphs[]`), writing `<i>.wav` / `title.wav` into the existing layout so `just_audio` plays them unchanged.
6. Run the whole flow in **airplane mode**.

### Measurements (record per engine/voice, per device)
| Metric | How measured | Target |
|--------|--------------|--------|
| First-paragraph latency | ms from request → audio ready | < 1.5 s flagship |
| Real-time factor (RTF) | synth_time ÷ audio_duration | < 1.0 (faster than playback) |
| Model size on disk | file bytes | note for delivery decision |
| Peak memory | profiler during synth | no OOM; note dual-model cost |
| Battery / thermal | 20-min continuous read: % drop + peak temp | "comfortable", no throttling |
| Quality | blind A/B vs current edge-tts, 5 listeners | ≥ parity, ideally better |

---

## 3. Part B — Server-side Piper/Kokoro POC (Python)

**Goal:** prove `app/api/tts.py` can produce the same voices without edge-tts.

1. In a scratch script, synthesize a paragraph with **`sherpa-onnx` (Python, native lib — no subprocess)** using the same model files as Part A.
2. Keep the existing dual-voice segmentation + `_TTS_SEMAPHORE` concurrency cap; swap only the per-segment call.
3. Benchmark: RTF and throughput vs edge-tts for a full chapter on the deployment instance class.
4. **If a CLI path is trialed** instead of the library, use the safe pattern from architecture §5 (list args, text via stdin, `shell=False`, `timeout=`, voice→model allowlist) — never interpolate user text into a shell.

**Acceptance:** identical voice to Part A; RTF acceptable for the server tier; no shell-injection surface.

---

## 4. Part C — Model delivery decision

Using Part A sizes:
- If chosen model ≤ ~90 MB **and** install size acceptable → consider **bundling**.
- Else → **download-on-first-run**: small binary, model fetched to app documents with a **checksum verify** + re-download-on-corrupt (mirror the repair loop in `download_service.dart`), progress UI, then fully offline.

**Default lean:** download-on-first-run (keeps the store binary small, esp. for Kokoro).

---

## 5. Engine decision — **Kokoro (chosen)**

Engine selected: **Kokoro** — best quality and clean single-model dual-voice
(narrator/dialogue via speaker ids). The POC's job is now to **validate Kokoro
meets the RTF/thermal targets on the OnePlus 15**, not to A/B it. **Piper is the
fallback only if** Kokoro can't hit real-time or runs too hot on target devices.

The scoring grid below is retained for that go/no-go check and for the low-end
device call:

| Criterion | Weight | Piper | Kokoro |
|-----------|--------|-------|--------|
| Voice quality | 35% | | |
| Speed (RTF) on OnePlus 15 | 20% | | |
| Battery / thermal | 15% | | |
| Dual-voice ergonomics | 15% | (2 models) | (multi-sid, 1 model) |
| Model size / delivery | 15% | (small) | (large) |

Heuristic going in: **Kokoro** if flagship RTF < 1.0 and thermals are fine (best quality + clean dual-voice); **Piper** as the light, battery-friendly, guaranteed-real-time fallback (and for mid-range devices).

---

## 6. Acceptance criteria (POC done when…)

1. A real chapter plays **dual-voice, fully offline** on the OnePlus 15 via `sherpa_onnx`, cached into `downloads/<id>/`.
2. Per-engine measurements (§2) recorded for Piper and Kokoro.
3. Python backend synthesizes the **same voice** with no edge-tts and no shell-injection surface.
4. A written engine recommendation + delivery decision, filled into §5.
5. Desktop (macOS) smoke test confirms the cross-platform claim.

---

## 7. Rough effort

| Task | Est. |
|------|------|
| sherpa_onnx wired + `.wav` output | 1–2 d |
| DualVoiceSegmenter port + dual-voice | 1 d |
| 3-chapter offline run + measurements | 1 d |
| Python backend bench | 0.5–1 d |
| Delivery decision + write-up | 0.5 d |

---

## 8. Risks

| Risk | Mitigation |
|------|-----------|
| sherpa_onnx iOS/desktop build friction | Validate Android + macOS early in Part A |
| Kokoro too slow/hot on mid devices | Rubric weights RTF/thermal; Piper fallback |
| espeak-ng data path/config issues | Follow sherpa_onnx VITS example configs first |
| WAV cache size | Measure; transcode to MP3 later only if needed |
