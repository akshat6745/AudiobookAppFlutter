# .ai-context/

Context files for AI agents working on this codebase. Read these **before** exploring source files to save tokens.

## Files

| File | Contents | When to read |
|------|----------|-------------|
| `CONTEXT.md` | Full reference: architecture, providers, models, patterns, routing, known issues | **Always — start here** |
| `CHANGES.md` | Chronological log of significant changes made by AI agents | When debugging regressions or understanding recent decisions |

## Usage tip

For most tasks, reading `CONTEXT.md` alone gives enough orientation to avoid reading 30+ source files.
Only drill into individual source files for the specific area you're changing.

## Updating these docs

After making significant architectural changes, update `CONTEXT.md` and append a dated entry to `CHANGES.md`.
Keep entries brief — bullet points, not prose.
