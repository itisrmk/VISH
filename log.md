# vish execution log

Append-only operational log. Entries are added automatically by `.claude/hooks/append-log.sh` on every Bash/Write/Edit tool use (PostToolUse hook configured in `.claude/settings.json`). Manual session summaries are added as level-3 headings.

Format of auto-entries: `` - `UTC timestamp` **Tool** — description — `command-or-path` ``

---

### 2026-04-23 — Phase 0 kickoff

- Session started. CLAUDE.md + ROADMAP.md reviewed.
- Plan drafted and persisted to `docs/PHASE_1_PLAN.md`.
- `vish-engineer` agent created at `.claude/agents/vish-engineer.md` with §10 invariants + mandatory two-pass (correctness → performance) workflow.
- Logging hook installed at `.claude/settings.json` + `.claude/hooks/append-log.sh`. Hook script self-test passed. **Activates on next session start** — Claude Code reads settings.json at session init, not hot-reload.
- `git init` on branch `main`; initial commit `2731074` (10 files, 1001 insertions) with planning + infra baseline.
- 5 of 6 OSS references shallow-cloned into `third-party/reference/` (gitignored). SHAs recorded in `third-party/SOURCES.md`. Commit `1bc62b6`.
- sparkle-updater reference: upstream URL `ahkohd/tauri-plugin-sparkle-updater` returned 404. Deferred to pre-Week-4 — either locate a live fork or bridge `sparkle-project/Sparkle` directly via objc2. Noted in `SOURCES.md` followups.
- Phase 0 spike S3 (global-hotkey ⌥Space) launched in background via `general-purpose` subagent, instructed to load and obey `.claude/agents/vish-engineer.md` as its operating contract (actual `vish-engineer` subagent not yet runtime-registered — will be directly invokable next session).
- **Spike S3 result: PASSED (compile-time).** Agent delivered 35-line `src/main.rs` using `global-hotkey 0.7` + `objc2-app-kit 0.3` `NSApplicationActivationPolicy::Accessory`, registers ⌥Space, event thread logs `id` + `state` via structured `tracing`. Pass 2 removed two unnecessary `unsafe` blocks (objc2-app-kit 0.3 exposes `setActivationPolicy`/`run` as safe). Verified independently: `cargo check` + `cargo clippy --all-targets -- -D warnings` both clean. **Runtime validation left to human:** `cd third-party/spikes/s3-hotkey && cargo run`, press ⌥Space, expect `hotkey fired … state=Pressed/Released` log lines. AX prompt on launch = spike failed → trigger risk R2 (⌥⌘Space fallback).

### 2026-04-23 — Phase 0 continuation (same session, hook still dormant)

- Verified hook is still inactive this session (no auto-entries added between turns). Confirmed same-session state.
- **S2+S4 merged into one combined spike.** Rather than two sequential spikes, one crate at `third-party/spikes/s2-gpui-stack/` forces the full UI-side dependency graph `[gpui + gpui-component + objc2 + objc2-app-kit + dispatch2]` into a single compile unit. More informative failure mode than two separate checks. Delegated to vish-engineer-surrogate (general-purpose agent bound to the vish-engineer.md contract) running in background; agent instructed to WebFetch gpui-component's pinned `gpui` rev rather than guessing, with 3-retry cap and versions-that-worked recorded in a RESULTS.md for CLAUDE.md §2 pin update.
- **S1 script committed** at `third-party/spikes/s1-mlx/run.sh` + README. Uses `mlx-community/SmolLM2-135M-Instruct-4bit` (~80MB) since the spike is protocol-only — real Llama-3.1-8B-Q4 download deferred to Phase 3. Script running in background; first run includes one-time `uv run --with mlx-lm` install. Pass criterion: OpenAI SSE `data: {...}` chunks + `data: [DONE]` terminator.
- Commits `c46e13e` (S1 script).

---
- `2026-04-24T04:46:47Z` **Bash** — Hook self-test — `echo test `
