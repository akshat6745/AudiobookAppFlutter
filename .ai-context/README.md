# .ai-context/

Context files for AI agents working on this codebase. Read these **before** exploring source files to save tokens.

## Files

| File | Contents | When to read |
|------|----------|-------------|
| `AUDIOBOOK_HIGH_LEVEL_MAP.md` | Cross-repo high-level architecture, worktree topology, guardrails, change summary, and media playback overview | **First stop for cross-repo (Python + R2 Worker + Flutter) context** |
| `AUDIOBOOK_LOW_LEVEL_MAP.md` | Commit-by-commit technical map across Python & Flutter, API/R2 contracts, and line-by-line media playback deep-dive | **When debugging backend/worker/Flutter integration or audio playback** |
| `CONTEXT.md` | Flutter-specific reference: architecture, providers, models, patterns, routing, known issues | **Always before editing Flutter source files** |
| `CHANGES.md` | Chronological log of significant changes made by AI agents in Flutter | When debugging regressions or understanding recent decisions |

## Usage tip

For most tasks, reading `CONTEXT.md` alone gives enough orientation to avoid reading 30+ source files.
Only drill into individual source files for the specific area you're changing.

## Updating these docs

After making significant architectural changes, update `CONTEXT.md` and append a dated entry to `CHANGES.md`.
Keep entries brief — bullet points, not prose.
