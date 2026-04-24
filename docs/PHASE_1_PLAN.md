# vish — Phase 0 / Phase 1 execution plan

> Source of truth for the gap between "greenfield repo" and Phase 1 Week 1 Day 1. ROADMAP.md owns the week-by-week narrative beyond Phase 1; this file owns pre-flight and the concrete Week 1-4 deliverables.

## 0. Decisions locked

| Decision | Value | Rationale |
|---|---|---|
| Signing (v0.1) | Ad-hoc, skip notarization | Dev ID deferred. DMG still works; Gatekeeper right-click-Open acceptable for dev distribution. |
| Global hotkey | ⌥Space | Per CLAUDE.md §2. ⌘Space collides with Spotlight. |
| Embedding model (Phase 2) | `bge-small-en-v1.5` via fastembed | 384-d, CPU-fine, matches roadmap. `nomic-embed` upgrade deferred until throughput hurts. |
| Crash reporting | GlitchTip (self-hosted), deferred to Week 13 | Self-host mandate per CLAUDE.md §10 (no third parties see user data). |
| Phase 3 model target | Llama-3.1-8B-Instruct-Q4 (MLX) | ~4.5GB weights + KV cache, fits 12GB ceiling. Expect ~30 tok/s on M2 Pro, ~20 tok/s on M1 base. |
| Workspace start version | `0.0.1` | `0.1.0` reserved for Phase 1 exit DMG. |
| Dev machine | Apple Silicon M1/M2, 16GB | Tight for 8B model — budget watch required in Phase 3. |

---

## 1. Phase 0 — pre-Week-1 (3–5 days, parallel-runnable)

### 1.1 Repo initialization (blocking, ~30 min)

```bash
cd /Users/rahulkashyap/Desktop/Projects/VISH
git init -b main
brew install git-lfs && git lfs install
```

**`.gitignore`:**
```
/target
/dist
**/*.rs.bk
.DS_Store
/third-party/reference/
/third-party/*/target
/third-party/mlx_sidecar/.venv
/third-party/mlx_sidecar/__pycache__
/resources/provisioning/*.p12
*.log
```

**`.gitattributes`:**
```
third-party/mlx_sidecar/** filter=lfs diff=lfs merge=lfs -text
resources/icons/*.icns filter=lfs diff=lfs merge=lfs -text
resources/icons/*.png filter=lfs diff=lfs merge=lfs -text
```

Initial commit: CLAUDE.md + ROADMAP.md + docs/PHASE_1_PLAN.md + .claude/ + .gitignore + .gitattributes + log.md.

### 1.2 Research spikes (half-day, parallel)

Four cheap validations in `third-party/spikes/`. Delete before Week 1.

| # | Spike | Time | Kill condition |
|---|---|---|---|
| S1 | `uv run mlx_lm.server --model mlx-community/Llama-3.1-8B-Instruct-4bit` → curl OpenAI-spec SSE | 30 min | SSE doesn't match spec → re-eval vish-llm architecture |
| S2 | Minimal GPUI + `gpui-component` hello-world. Pick SHA from `zed-industries/zed` HEAD today. | 1–2 hr | GPUI and gpui-component diverged → pin older `gpui-component` tag |
| S3 | Standalone `global-hotkey` bin registering ⌥Space. Confirm it fires **without** AX. | 1 hr | Silently fails → Apple changed Carbon surface; fallback to ⌥⌘Space |
| S4 | objc2 / dispatch2 / objc2-app-kit version combo compiling clean against GPUI's transitive objc2 | 1 hr | Mismatch → pin to GPUI's transitive versions |

### 1.3 Version pins (lock during Phase 0, record in CLAUDE.md §2)

After spikes pass, populate `[workspace.dependencies]`:

```toml
gpui = { git = "https://github.com/zed-industries/zed", rev = "<SHA from S2>" }
gpui-component = { git = "https://github.com/longbridge/gpui-component", rev = "<SHA from S2>" }
objc2 = "0.6"           # confirm matches GPUI transitive
objc2-app-kit = "0.3"
objc2-foundation = "0.3"
objc2-core-spotlight = "0.3"
objc2-event-kit = "0.3"
objc2-contacts = "0.3"
dispatch2 = "0.3"
global-hotkey = "0.7"
window-vibrancy = "0.6"
tray-icon = "0.22"
muda = "0.18"
notify = "7"
rusqlite = { version = "0.32", features = ["bundled", "load_extension"] }
tantivy = "0.23"
fastembed = "5"
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
thiserror = "2"
anyhow = "1"
interprocess = "2"
bincode = "1.3"
serde = { version = "1", features = ["derive"] }
plist = "1"
```

### 1.4 OSS reference forks (~30 min)

Read-only shallow clones into `third-party/reference/`. **Do not vendor** — study and port selectively.

```bash
mkdir -p third-party/reference && cd third-party/reference
git clone --depth 1 https://github.com/MatthiasGrandl/Loungy loungy-reference
git clone --depth 1 https://github.com/ahkohd/tauri-nspanel tauri-nspanel-reference
git clone --depth 1 https://github.com/ReagentX/imessage-exporter imessage-tools-reference
git clone --depth 1 https://github.com/ahkohd/tauri-plugin-sparkle-updater sparkle-updater-reference
git clone --depth 1 https://github.com/zed-industries/zed zed-reference
git clone --depth 1 https://github.com/pop-os/launcher pop-launcher-reference
```

Record cloned HEAD SHAs in `third-party/SOURCES.md` so bumps are deliberate.

### 1.5 Tool installs (~15 min + one-time Metal download)

```bash
# Required before first `cargo build` of the workspace.
# Xcode 26+ ships without the Metal toolchain; GPUI's build script invokes
# `xcrun metal …` to compile shaders and fails without it. ~700MB, one-shot.
xcodebuild -downloadComponent MetalToolchain

# Python sidecar toolchain. Phase 0 kickoff discovered uv was NOT actually
# present despite the initial questionnaire answer; verify with `command -v uv`:
#   curl -LsSf https://astral.sh/uv/install.sh | sh

# Remaining tools:
brew install create-dmg
cargo install --git https://github.com/zed-industries/cargo-bundle --branch zed-deploy cargo-bundle
# notarytool profile: deferred — Dev ID not yet provisioned
```

---

## 2. Phase 1 — Week 1 (workspace + dev loop)

**Files to create on Day 1:**

### `Cargo.toml` (workspace root)

```toml
[workspace]
resolver = "2"
members = [
    "apps/vish",
    "apps/vishd",
    "crates/vish-core",
    "crates/vish-index",
    "crates/vish-sources",
    "crates/vish-embed",
    "crates/vish-llm",
    "crates/vish-mlx",
    "crates/vish-macos",
    "crates/vish-ui",
]

[workspace.package]
version = "0.0.1"
edition = "2024"
license = "proprietary"
authors = ["Rahul Kashyap <rahul@foundertool.ai>"]

[workspace.dependencies]
# populate from §1.3 after spikes land

[profile.release]
lto = "thin"
codegen-units = 1
strip = "debuginfo"
panic = "abort"

[profile.dev]
opt-level = 1   # GPUI at opt-level 0 is unwatchable
```

### `rust-toolchain.toml`

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy", "rust-src"]
# GPUI SHA recorded in CLAUDE.md §2
```

### Per-crate stub `src/lib.rs`

Each crate gets a one-line doc comment describing its single responsibility (forces discipline — if you can't fit it on one line, the crate is wrong).

Example: `crates/vish-core/src/lib.rs`:
```rust
//! IPC protocol, shared types, and error taxonomy for vish.
//!
//! Dependency-light — imported by every process. No tokio, no objc2, no platform-specific deps.

pub mod proto;
pub mod error;
```

### `apps/vish/src/main.rs`

```rust
//! vish UI process — NSApp run loop host, GPUI root, hotkey registrar, tray manager.

fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    tracing::info!("vish starting");
    Ok(())
}
```

`apps/vish/Cargo.toml` must have `[[bin]] name = "vish"` — the bundle name depends on it.

### `scripts/dev.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export RUST_LOG="${RUST_LOG:-vish=debug,vishd=debug,info}"
export RUST_BACKTRACE=1
cargo run -p vish "$@"
```

### `scripts/reset-tcc.sh`

```sh
#!/bin/sh
tccutil reset All com.vish.launcher
tccutil reset All com.vish.indexer
```

Both `chmod +x`. Commit.

**Week 1 done when:** `./scripts/dev.sh` runs and logs `"vish starting"`. `cargo test --workspace` passes. `cargo clippy --workspace --all-targets -- -D warnings` passes.

---

## 3. Phase 1 — Week 2 (NSPanel + hotkey)

First real risk. Port from `tauri-nspanel-reference` into `crates/vish-macos`:
- `src/panel.rs` — NSPanel subclass, `.nonactivating`, override `canBecomeKeyWindow → YES` / `canBecomeMainWindow → NO`.
- `src/hotkey.rs` — `global-hotkey` event loop bridged to GPUI via channel.
- `src/vibrancy.rs` — wrapper around `window-vibrancy`.

`collectionBehavior` = `.canJoinAllSpaces | .fullScreenAuxiliary | .moveToActiveSpace`. Miss the last one and the panel doesn't follow Spaces.

**Exit test:** ⌥Space toggles a blurred, non-activating panel. Esc hides. Frontmost app keeps focus. No AX prompt. No debug warnings.

---

## 4. Phase 1 — Week 3 (GPUI components + first-paint budget)

Benchmark the 80ms first-paint target *before* adding state. Empty `TextField` + `ResultList` is the baseline.

Deliverables:
- `crates/vish-ui/src/theme.rs` — Zed token names, hard-coded light + dark. No theme system yet.
- `crates/vish-ui/src/root.rs` — `TextField` (top) + `ResultList` (below). Mock `Vec<Hit>` for layout.
- `os_signpost` markers around hotkey → first-paint. Measure via `xcrun xctrace`.

**Exit test:** cold hotkey → visible-blurred-panel-with-focused-TextField in <80ms on M1/M2. If you hit 120ms, profile — likely GPUI texture atlas warm-up on first frame.

---

## 5. Phase 1 — Week 4 (packaging, ad-hoc signed)

With Dev ID deferred, Week 4 is descoped:

`scripts/release.sh`:
```bash
cargo build --release -p vish
cargo bundle --release -p vish        # Zed fork of cargo-bundle
codesign --deep --force --sign - \
    --entitlements resources/entitlements.plist \
    target/release/bundle/osx/vish.app
create-dmg --volname "vish" --window-pos 200 120 --window-size 600 300 \
    --icon-size 100 --app-drop-link 450 150 \
    dist/vish-v0.1.0.dmg \
    target/release/bundle/osx/vish.app
```

**Exit test:** DMG mounts, app drags to /Applications, first launch requires right-click → Open (Gatekeeper warning — expected with ad-hoc), hotkey works, TCC state persists across launches.

**Deferred from original Week 4:**
- `notarytool submit` + `stapler staple`
- Sparkle appcast.xml on R2
- Full upgrade smoke test

**Still done:**
- Sparkle 2 code path integrated but no-op when `env!("VISH_SPARKLE_DISABLED")` set. Wiring ready; flipping to signed is one parameter change.
- Release script written so flipping to signed is a one-line edit.

---

## 6. Phase 2 — decisions, not plan

The roadmap covers weeks 5–14 at the right granularity. **Only lock these now:**

1. **FSEvents persistence:** `~/Library/Application Support/vish/fsevents.state` — single file with `lastEventId: u64` + per-source last-seen-rowid. No SQLite just for this.
2. **`vish-core` protocol freeze before Week 7.** After tantivy/sqlite persist, protocol bumps need migrations. Bikeshed Week 5, freeze.

**Replanning checkpoints** (stop and re-plan if slipped >2 weeks):
- End of Week 8 (P1 sources done — apps + files)
- End of Week 12 (embeddings + hybrid search working)

**Front-load Phase 2 risks:**
- `attributedBody` NSKeyedArchiver decoder (Messages) → spike in **Week 7** as standalone `vish-sources/src/messages/attributed_body.rs`, not Week 10. Buffer of 3 weeks if it takes 3 days.
- Mail `.emlx` parser → similar Week 7 spike against 100 real emails.

Both spikes happen while Weeks 7–8 are nominally on tantivy setup — no conflict.

---

## 7. Phase 3 & 4 — decisions only

Per roadmap's own rule: replan at phase boundaries. But:

- **Sidecar Unix-socket bridge:** `mlx_lm.server` binds TCP only. Spawn with `--host 127.0.0.1 --port 0`, parse bound port from stdout, forward via `interprocess`. If stdout port-parsing is unreliable, pick a fixed port.
- **RAG templates:** `include_str!` at compile time. Edits = recompile. Iterate in git.
- **Never-silent cloud fallback:** `CloudBackend::chat_stream` panics in debug builds if `config.allow_cloud != true`. Runtime-enforced §9 invariant.
- **Phase 4 extensions:** child process, JSON-line on stdio. Matches `pop-os/launcher` ecosystem.

---

## 8. Risk register (Phase 1 focused)

| # | Risk | Likelihood | Impact | Mitigation | Owner-week |
|---|---|---|---|---|---|
| R1 | GPUI SHA + gpui-component incompatibility | Medium | High (blocks Week 3) | S2 spike; pin older `gpui-component` if blocked | Phase 0 |
| R2 | ⌥Space hotkey silently fails due to AX changes | Low | High (product dead) | S3 spike; fallback ⌥⌘Space | Phase 0 |
| R3 | NSPanel focus-steal regression on current macOS | Medium | High | Test on 14.x, 15.x, current | Week 2 |
| R4 | First-paint >80ms | Medium | Medium | Profile Week 3, do not ship past target | Week 3 |
| R5 | `cargo-bundle` Zed fork outdated | Low | Medium | Phase 0 `cargo bundle --help` smoke test | Phase 0 |
| R6 | M1/M2 16GB Llama-3.1-8B-Q4 below target tok/s | Medium | Medium | Benchmark during S1; switch to Qwen2.5-7B-Q4 or accept lower bar | Phase 0 |
| R7 | `attributedBody` parser rot between macOS versions | Medium | Medium | Week 7 spike, not Week 10 | Week 7 |

---

## 9. Day-1 action list

1. `git init` + commit CLAUDE.md/ROADMAP.md/PHASE_1_PLAN.md.
2. Spike S1 — `mlx_lm.server` OpenAI-spec curl. Record port-bind behavior. (30 min)
3. Spike S3 — `global-hotkey` ⌥Space standalone bin. (1 hr)
4. Spike S2 — GPUI + gpui-component hello-world, pick SHA pair. (1–2 hr)
5. Spike S4 — objc2/dispatch2 compat check. (1 hr)
6. Update CLAUDE.md §2 with pinned versions. Commit.
7. Clone references into `third-party/reference/`. Record SHAs in `third-party/SOURCES.md`. Commit.
8. Start Week 1 — workspace scaffolding.

Day-1 output: repo exists, spikes green, SHAs pinned, Week 1 begins Day 2.
