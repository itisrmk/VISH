# VISH Production Readiness

## UX Gates

- First launch shows onboarding only after `ColdLaunchReady`; it must never block the menu bar item or launcher prewarm.
- Onboarding has four steps: value, permissions, feature defaults, ready. Every step must be skippable or finishable without granting optional permissions.
- Settings opens lazily and starts no launcher-hot-path work. Ollama checks happen only from Settings or explicit AI use.
- The Settings Setup pane is the source of user-facing readiness: Launcher, Files, Clipboard, AI, and Privacy. Each card must show one status and one next action.
- Optional features remain trigger-based: files through file commands, clipboard through `clip` / `clipboard`, snippets through `;`, AI through `ai` / `?` / Tab actions.
- Full Disk Access is an OS permission; folder-level control is handled by VISH exclusions in Settings > Files and must apply to Spotlight, fallback catalog, semantic vectors, and file watcher paths.

## Performance Gates

| Area | Production target | Validation |
|---|---:|---|
| Cold launch | <=120 ms | `./scripts/benchmark.sh` |
| Hotkey to first frame | <=16 ms p95 | Instruments Points of Interest + `scripts/signpost-report.sh` |
| Keystroke to rendered result | <=16 ms p95 | Instruments Points of Interest + `scripts/signpost-report.sh` |
| Spotlight query | <=30 ms p95 | Instruments Points of Interest + `scripts/signpost-report.sh` |
| Idle RSS | <=80 MB | `./scripts/benchmark.sh` |
| Idle CPU | 0.0% average | `./scripts/benchmark.sh` |
| Warm AI first token | <=1500 ms | `./scripts/ai-benchmark.sh` |
| Warm embedding batch | <=500 ms | `./scripts/ai-benchmark.sh` |
| Settings progress updates | <=4 Hz | Code review / Instruments if indexing regresses |

## Release Flow

- Run `xcodegen generate` after adding/removing Swift files.
- Run Debug build before UI handoff.
- Run Release smoke benchmark after performance-adjacent changes.
- Run AI benchmark after Ollama, model picker, AI streaming, embedding, or semantic index changes.
- Do not call Settings/onboarding polished until there is a visual check and the latest benchmark numbers are logged.

## Current Gaps

- Need a real Instruments trace for hotkey, keystroke, and Spotlight p95 before claiming all frame-level budgets.
- Need full VoiceOver pass through launcher, Settings, and onboarding.
- Need Developer ID credentials, notarized DMG, and production appcast hosting for true external distribution. Sparkle feed/key wiring and local signed appcast generation are in place.
