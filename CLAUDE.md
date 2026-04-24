# CLAUDE.md — vish

> This file is read by Claude Code at the start of every session. It is the single source of truth for what vish is, how it is built, and what constraints are non-negotiable. Update it when architectural decisions change. Do not duplicate its content in other docs.

## 1. Project identity

**vish** is a native macOS AI launcher — a single keystroke away, GPU-rendered, locally-inferred, and aware of everything on the user's Mac. It is the intersection of three existing product categories that nobody has yet combined in one binary:

- **Raycast / Alfred** — global hotkey, fuzzy-searchable command palette, extensions
- **ChatGPT desktop** — streaming chat with tools, conversation history, long context
- **Spotlight / Copilot Recall** — universal index of mail, messages, browser history, calendar, notes, files

The product thesis is that RAG *over the user's own Mac* is the feature that a local chatbot has and a cloud chatbot cannot. A Rust ChatGPT clone has no moat. A local AI that answers *"when did I last talk to Sarah about the thesis defense"* against the user's actual messages, mail, and calendar — on-device, notarized, no cloud — does.

**Non-goals.** Cross-platform parity (Linux/Windows are deferred indefinitely). App Store distribution (the sandbox forbids Full Disk Access and we need it). A plugin marketplace (v1). A new inference engine (we integrate MLX, we don't reinvent it).

## 2. Tech stack (and why)

Every choice here has a rationale rooted in the "Zed-level polish + MLX performance + universal indexing" constraints. Do not substitute without updating this section.

**UI layer: GPUI** sourced from `zed-industries/zed`, not the crates.io `gpui` v0.2.x (which is a name-squat). GPUI is the only Rust framework that produces 120Hz ProMotion-native output on macOS today. Tauri's WKWebView has a hard 60 FPS ceiling. egui/Iced are not Mac-native. **Pinning strategy (Phase 0 spike S2):** in `[workspace.dependencies]`, declare `gpui = { git = "https://github.com/zed-industries/zed" }` **without** a `rev` — it dedupes with gpui-component's transitive resolution, producing a single Zed clone instead of two. Reproducibility comes from committed `Cargo.lock`; bump gpui by editing the lock deliberately, never via `cargo update`. Cost: weekly breaking changes absorbed when we bump the lock. **Widgets: `longbridge/gpui-component`** — the shadcn/ui of GPUI, Apache-2.0 — pinned to `rev = "808df4069295ef4e0b3b01445671c3c7057377cd"` (2026-04-23 main HEAD, compile-verified by S2+S4); covers buttons/inputs/code editor/markdown/dock/charts.

**macOS integration: the objc2 family** — `objc2 = "0.6"`; 0.3-line for `objc2-app-kit`, `objc2-foundation`, `objc2-core-spotlight`, `objc2-event-kit`, `objc2-contacts`; `dispatch2 = "0.3"`. No cacao, no legacy `objc` crate. **Feature-flag rule (Phase 0 spike S4):** 0.3-line `objc2-*` crates default to zero bindings exposed — for each type referenced, declare its feature **and every feature it transitively inherits from**. Example: `NSApplication` requires `features = ["NSApplication", "NSResponder"]` because `NSApplication` inherits from `NSResponder`. Add per-type as first referenced; never enable everything globally. For media/capture escape hatches, **cidre** (yury/cidre).

**Inference: subprocess to `mlx_lm.server`** as the primary path, bundled via `uv`-managed embedded Python in the app bundle. OpenAI-compatible SSE on localhost. This is what Ollama 0.19 does internally; it's what every serious local-LLM app converges to. **Fallback in-process: `mistral.rs`** with `--features "metal accelerate"` for a pure-Rust deploy option once the product is proven. **llama-cpp-2** for GGUF coverage when users import models from Ollama/HF. Never Candle (Metal backend is too buggy as of 2026).

**Indexing: SQLite + tantivy + sqlite-vec.** SQLite is the canonical metadata store (one table per source). tantivy owns BM25 full-text. sqlite-vec handles vectors up to ~500k docs; we upgrade to LanceDB only when we prove we need it. **Embeddings: `fastembed-rs`** with `bge-small-en-v1.5` initially; upgrade path to Candle+Metal with `nomic-embed-text-v1.5` (Matryoshka-truncatable) when throughput matters. Hybrid retrieval via Reciprocal Rank Fusion (k=60).

**Filesystem: `notify` v7** for FSEvents. Exclude `Library/Caches`, `node_modules`, `.git/objects`, `build`, `target`. Persist `lastEventId` across daemon restarts so nothing is missed.

**Global hotkey: `global-hotkey`** (tauri-apps, Carbon `RegisterEventHotKey` under the hood — does not require Accessibility permission for modifier+key chords). Default: **⌥Space** (⌘Space collides with Spotlight).

**Window chrome: `window-vibrancy`** for NSVisualEffectView blur, **`tray-icon` + `muda`** for status item and menus. The popup is an `NSPanel` with `.nonactivating` style so focus never steals from the frontmost app — the Raycast pattern. Crib from `tauri-nspanel` (~40 lines of objc2).

**IPC: Unix domain sockets + length-prefixed bincode.** One socket for UI↔daemon, one for UI↔inference. `interprocess` crate for the transport. No gRPC, no XPC, no shared memory unless profiling proves we need it.

**Async runtime: GCD-backed executor for the UI process** (ForegroundExecutor on `dispatch_get_main_queue()`, BackgroundExecutor on a concurrent queue, wired through `async-task` Runnables — the pattern Zed uses because tokio cannot drive NSApp's run loop correctly). **Tokio multi-thread runtime on non-main threads** in the daemon and for HTTP/IPC in the UI.

**Packaging: Zed's fork of `cargo-bundle`** (`zed-industries/cargo-bundle`, `zed-deploy` branch). Developer ID + `notarytool` (never `altool` — dead since Nov 2023) + `stapler`. Never MAS.

**Auto-update: Sparkle 2 via objc2 bridge.** Static appcast XML on Cloudflare R2. Crib the objc2 wrapper pattern from `tauri-plugin-sparkle-updater`.

## 3. Architecture

vish is **three processes** that talk over Unix sockets. This is not architectural flex — it's the only way to get crash isolation, correct TCC boundaries, and sane memory reclaim on macOS.

```
┌─────────────────────────┐
│   vish (UI, .app)       │  NSApp run loop, GPUI, hotkey, tray
│   LSUIElement = YES     │  Lives: always (LaunchAgent optional)
└───────┬─────────────────┘
        │ Unix socket: ~/Library/Application Support/vish/ipc.sock
        │ bincode, length-prefixed
        ▼
┌─────────────────────────┐
│   vishd (indexer)       │  FSEvents, parsers, tantivy, sqlite
│   LaunchAgent, RunAtLoad│  Lives: always (survives UI quit)
└─────────────────────────┘
                           Unix socket: /tmp/vish-inference.sock
                           OpenAI-compatible SSE
        ┌─────────────────────────┐
        │   vish-inference        │  mlx_lm.server (Python sidecar)
        │   Spawned on demand     │  or mistral.rs in-process worker
        └─────────────────────────┘
```

**Why separate `vishd`:** FSEvents and file parsing are I/O-heavy and must not block the UI. Indexing survives UI quit so the user's data stays fresh. `vishd` has its own TCC principal — Full Disk Access is granted to its binary path, not the UI binary — because that's how macOS actually scopes permissions (TCC is signing-hash-tied).

**Why separate `vish-inference`:** Metal OOM is the most common failure mode at ≥14B models on 16GB machines. Killing a child returns GPU memory to the OS immediately. macOS does not aggressively free Metal buffers within a long-lived process. Separate process = clean reclaim. Also clean distribution boundary for the Python sidecar.

**Threading invariants (violate these and you get flickers, beachballs, or crashes):**

- Every AppKit API call must happen on the main thread. Use `dispatch2` to hop.
- Nothing on the main thread may block for more than 8ms. At 120Hz that drops a frame.
- Metal drawable acquisition must have `setAllowsNextDrawableTimeout:YES` (Zed issue #53390 documents the indefinite-hang failure mode when it's NO).
- Long-running LLM decode loops get a dedicated OS thread, not a tokio task. Cooperative schedulers starve on multi-second blocking work.

## 4. Directory layout

vish is a Cargo workspace. Every crate has a single responsibility.

```
vish/
├── Cargo.toml                    # [workspace]
├── CLAUDE.md                     # this file
├── ROADMAP.md                    # phased plan with milestones
├── apps/
│   ├── vish/                     # UI binary (the .app contents)
│   │   ├── src/main.rs
│   │   ├── build.rs              # invokes cargo-bundle on release
│   │   └── Info.plist
│   └── vishd/                    # indexer daemon binary
│       ├── src/main.rs
│       └── com.vish.indexer.plist  # LaunchAgent
├── crates/
│   ├── vish-core/                # IPC protocol, shared types, errors
│   ├── vish-index/               # tantivy schema, sqlite migrations, sqlite-vec glue
│   ├── vish-sources/             # per-source parsers (see §7)
│   ├── vish-embed/               # embedding backends (fastembed, candle-metal)
│   ├── vish-llm/                 # Backend trait + mlx_lm.server client + mistral.rs
│   ├── vish-mlx/                 # Python sidecar manager (spawn, health, shutdown)
│   ├── vish-macos/               # objc2 glue, AX, NSPanel, Sparkle, hotkey plumbing
│   └── vish-ui/                  # GPUI views, components, theming
├── scripts/
│   ├── dev.sh                    # cargo run with dev signing
│   ├── release.sh                # sign + notarize + staple + DMG
│   ├── reset-tcc.sh              # tccutil reset for local dev
│   └── bootstrap-sidecar.sh      # uv venv + mlx-lm install into bundle
├── resources/
│   ├── Info.plist                # LSUIElement=YES, bundle id, version
│   ├── entitlements.plist        # JIT, unsigned-exec-mem, AX, network
│   ├── entitlements-vishd.plist  # FDA-requesting entitlements
│   └── icons/
└── third-party/
    └── mlx_sidecar/              # uv-managed Python venv, committed via git-lfs
```

No `src/lib.rs` at the workspace root. No `utils` crate. No "common" dumping ground. If something doesn't fit an existing crate, the discipline is to name it properly first.

## 5. Coding conventions

**Rust edition 2024. MSRV tracks stable.** No nightly features unless GPUI requires one (it currently does not as of the pinned SHA).

**Error handling.** `thiserror` for library crates (`vish-core`, `vish-index`, `vish-sources`, `vish-embed`, `vish-llm`). `anyhow` is permitted only in `apps/vish/src/main.rs` and `apps/vishd/src/main.rs` at the top-level error boundary. Never in a library.

**Async.** Prefer `async fn` over manual `Future` impls. Use `tokio::select!` for cancellation. Never spawn a task without storing the `JoinHandle` — leaked tasks mask bugs. For LLM decode loops, use `std::thread::spawn` and bridge to async with `tokio::sync::mpsc`.

**Logging.** `tracing` + `tracing-subscriber`. JSON logs in release, pretty in dev. Structured fields, no format-string interpolation of runtime data (`tracing::info!(user_id = %id, "opened chat")` not `info!("opened chat for {}", id)`).

**No `unwrap()` in app code.** `expect("reason")` with a real message is fine at startup (config loading, where panic-on-fail is correct). Tests may unwrap freely.

**FFI safety.** All `unsafe` blocks get a `// SAFETY:` comment explaining the invariant. Prefer `objc2`'s safe wrappers over raw `msg_send!` unless the binding is missing — in which case open an upstream issue and wrap it locally.

**Formatting.** `rustfmt` on save, `clippy -- -D warnings` in CI. `clippy::pedantic` is too noisy for this codebase; stick to default + `clippy::nursery`.

**Tests.** Unit tests colocated (`mod tests` in the same file). Integration tests in `tests/` at the crate level. The daemon ships with a `--dry-run` mode that indexes a fixture directory — used by CI. Do not write snapshot tests against SQLite binary dumps; they churn on every schema bump.

## 6. IPC protocol

Length-prefixed bincode, not JSON. Schema lives in `vish-core/src/proto.rs` as Rust types that derive `Serialize`/`Deserialize`. Every message has a `request_id: u64` for correlation.

```rust
pub enum UiToDaemon {
    Search { query: String, limit: u32, sources: SourceFilter },
    Reindex { source: Source },
    Status,
    Shutdown,
}

pub enum DaemonToUi {
    SearchResults { request_id: u64, hits: Vec<Hit> },
    IndexProgress { source: Source, done: u64, total: u64 },
    Error { request_id: u64, code: ErrorCode, message: String },
}
```

Breaking protocol changes bump `vish-core`'s minor version and require both binaries to be rebuilt together. We do not support running mismatched versions — the UI checks `vishd`'s reported version on handshake and refuses to talk if it doesn't match.

For the inference sidecar, we speak OpenAI Chat Completions verbatim (including `stream: true` SSE). No custom protocol — this lets us swap between `mlx_lm.server`, `mistral.rs --interactive-mode http`, Ollama, and any cloud fallback with a config change.

## 7. Data source matrix

Per-source parsers live in `vish-sources`. Each source is a module implementing the `Source` trait: `initial_scan()`, `incremental(event: FsEvent)`, `schema_version() -> u32`. All sources tolerate the source app running (WAL mode, `?mode=ro&immutable=1` where supported, copy-to-tmp fallback otherwise).

| Source | Path | Format | Epoch | Status |
|---|---|---|---|---|
| Chrome/Arc/Brave | `~/Library/Application Support/<vendor>/.../History` | SQLite | Webkit µs since 1601 | P2 |
| Safari | `~/Library/Safari/History.db` | SQLite | Cocoa (s since 2001) | P2 |
| Firefox | `~/Library/Application Support/Firefox/Profiles/*/places.sqlite` | SQLite | PRTime µs since 1970 | P2 |
| Mail | `~/Library/Mail/V*/MailData/Envelope Index` + `.emlx` | SQLite + RFC822 | Unix | P2 |
| Messages | `~/Library/Messages/chat.db` | SQLite + NSKeyedArchiver blob | Cocoa ns | P2 |
| Calendar | EventKit via `objc2-event-kit` | Apple API | — | P2 |
| Contacts | `objc2-contacts` (CNContactStore) | Apple API | — | P2 |
| Apps | `/Applications`, `/System/Applications`, `~/Applications` | `.app` + Info.plist | — | P1 |
| Files | `$HOME` minus excludes | FSEvents + fs walk | — | P1 |
| Notes | `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` | SQLite + gzip'd protobuf | Cocoa | P3 (defer) |

**P1 = Phase 2 milestone 1 (apps and files are the MVP launcher). P2 = Phase 2 milestone 2. P3 = deferred.** Apple Notes requires a custom gzip+protobuf parser; encrypted notes require PBKDF2-SHA256+AES-GCM and are out of scope for v1.

**Messages gotcha:** on Ventura+, `message.text` is often NULL and the real text lives in `attributedBody` as an NSKeyedArchiver blob. Port the decoder from `imessage_tools` — do not write it from scratch.

**Mail gotcha:** `.emlx` is 4-byte-length prefix + RFC822 body + trailing plist. The envelope index gives you subject/from/to/date; the body requires reading the `.emlx`.

## 8. Permissions and signing

**TCC permissions required:**

- **Accessibility** (UI binary only) — for window switching and paste-on-select. Check via `AXIsProcessTrustedWithOptions({kAXTrustedCheckOptionPrompt: false})`. Prompt only on first use.
- **Full Disk Access** (daemon binary only) — probe for EACCES on `~/Library/Safari/Bookmarks.plist`; on denial, deep-link to `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
- **Contacts, Calendar, Reminders** — standard `requestAccess` prompts via EventKit/Contacts. Ask at first index.
- **Automation** (optional) — only if we add AppleScript bridges later.

TCC is **signing-hash-tied**. Every unsigned dev build resets permissions. Develop with a stable ad-hoc signing identity and keep `scripts/reset-tcc.sh` handy:

```bash
#!/bin/sh
tccutil reset All com.vish.launcher
tccutil reset All com.vish.indexer
```

**Entitlements (UI):** `com.apple.security.cs.allow-jit`, `com.apple.security.cs.allow-unsigned-executable-memory` (Metal MPS needs it), `com.apple.security.network.client`.

**Entitlements (daemon):** as above plus no sandbox — we need FDA. `com.apple.security.app-sandbox` is explicitly false.

**Never** use `com.apple.security.cs.disable-library-validation` unless absolutely forced. It trips Gatekeeper warnings even when notarized.

**Child processes stay inside the .app bundle** (`Contents/MacOS/vish-inference`, `Contents/Resources/mlx_sidecar/`). Processes outside the bundle have separate TCC principals and silently fail authorization. This is the single biggest source of "works in dev, broken on user's machine" bugs.

## 9. Build and release

**Dev loop:**
```
./scripts/dev.sh           # cargo run with ad-hoc signing, dev TCC
cargo test --workspace     # runs unit + integration tests
cargo clippy --workspace -- -D warnings
```

**Release:**
```
./scripts/release.sh v0.1.0
# → cargo build --release
# → cargo-bundle (Zed fork, zed-deploy branch)
# → codesign --deep --force --timestamp --options runtime \
#     --entitlements resources/entitlements.plist \
#     --sign "Developer ID Application: ... (TEAMID)" \
#     target/release/bundle/osx/vish.app
# → create-dmg
# → xcrun notarytool submit dist/vish-v0.1.0.dmg --keychain-profile AC_PROFILE --wait
# → xcrun stapler staple dist/vish-v0.1.0.dmg && xcrun stapler staple vish.app
# → upload DMG and appcast.xml to R2
```

Keychain profile `AC_PROFILE` is set up once via `xcrun notarytool store-credentials`. Never commit App Store Connect API keys.

Version bumps: edit `Cargo.toml` workspace version, `Info.plist` `CFBundleShortVersionString`, and `appcast.xml` `sparkle:version`. A pre-commit hook keeps them in sync.

## 10. Non-negotiable invariants

These are the rules that, if violated, produce the bugs that take days to diagnose. Claude Code must enforce them in every change.

1. **AppKit on main thread only.** Always.
2. **Main thread work under 8ms.** Profile with Instruments before claiming a feature is done.
3. **Metal drawable timeout enabled.** Never disable it "for performance."
4. **All child processes inside the .app bundle.**
5. **Daemon and UI are always version-matched at handshake.** No "tolerant" cross-version IPC.
6. **No `unwrap()` outside tests and one-time startup config.**
7. **Every SQLite open uses `?mode=ro&immutable=1` for foreign databases** (Safari, Chrome, Messages). Never open a running app's DB in read-write mode.
8. **Inference runs out-of-process by default.** In-process only behind a cargo feature flag, for advanced users.
9. **No telemetry without a privacy review.** Ever. The product's value is that data stays on-device.
10. **`global-hotkey` is the only hotkey API.** Do not sprinkle `NSEvent.addGlobalMonitor` calls around — it requires AX permission and can't consume events.

## 11. When you (Claude Code) are uncertain

If a task is ambiguous, stop and ask. If a library's API has changed (GPUI bumps, mlx-lm schema changes, objc2 Xcode SDK regen), prefer reading the current source over guessing from training data. If a design choice is being introduced that isn't covered above, update this file in the same commit as the code change — never let CLAUDE.md drift behind reality.

The user is a PhD-level Rust/AI systems developer building this solo. Optimize for correctness and systems depth over feature velocity. A shipped feature with a main-thread block is worse than a deferred one.
