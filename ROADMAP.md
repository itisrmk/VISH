# ROADMAP.md — vish

> The 12-month solo execution plan. Each phase has a single demo-able artifact as its exit criterion. Slippage on a milestone re-plans the phase, not the product.

## Guiding principles

**Ship a vertical slice end-to-end before going wide.** Phase 1 produces a notarized, auto-updating empty launcher — not an empty `cargo init`. Phase 2 indexes *two* sources well (apps + files) before touching mail/messages. Phase 3 has a working chat before we touch RAG. Each phase ends with something a user could actually run.

**Fork, don't scaffold.** Start from Loungy for the UI shell. Steal the `picker` crate pattern from Zed. Crib the `NSPanel` wrapper from `tauri-nspanel`. Port `imessage_tools`'s `attributedBody` decoder. Write from scratch only what no OSS project has already solved.

**The MLX-in-Rust gap is the single largest risk.** We mitigate it by running `mlx_lm.server` as a Python sidecar in Phase 3. If `mlx-rs` reaches production readiness during Phase 4, we migrate. If not, we stay on the sidecar forever — that's fine.

---

## Phase 1 — Scaffolding and UI shell (4 weeks)

**Goal: a notarized, signed, auto-updating `.app` that opens an empty NSPanel on ⌥Space and has a tray icon. Nothing else.**

### Week 1 — workspace and dev loop
- Cargo workspace with the crate layout from CLAUDE.md §4. Every crate has a doc comment explaining its one job.
- Fork Loungy locally at `third-party/loungy-reference/`. Do not vendor its code — read it for patterns and selectively port into `vish-macos` and `vish-ui`.
- Pin GPUI to a known-working SHA from `zed-industries/zed`. Record the SHA in `rust-toolchain.toml` comments and in CLAUDE.md.
- `./scripts/dev.sh` runs `cargo run -p vish` with ad-hoc signing. Terminal output confirms the binary launched.

### Week 2 — NSPanel popup + hotkey
- `vish-macos`: `global-hotkey` registration for ⌥Space, NSPanel creation with `.nonactivating` style, `collectionBehavior = .canJoinAllSpaces | .fullScreenAuxiliary`, level `.floating`. Window starts hidden at `(-10000, -10000)` to avoid first-show flicker.
- `window-vibrancy` integration for NSVisualEffectView blur.
- `tray-icon` + `muda` status item with a "Quit" menu entry.
- **Exit:** press ⌥Space, an empty blurred panel appears centered on the active screen. Press Esc, it hides without stealing focus.

### Week 3 — GPUI component integration
- Pull `longbridge/gpui-component` into the workspace. Render a placeholder TextField and ResultList inside the NSPanel. Wire the TextField focus to the panel's becomeKey event.
- First-paint under 80ms from hotkey press (measure with `os_signpost`).
- Theming primitives — color tokens, spacing scale, typography scale — live in `vish-ui/src/theme.rs`. Steal the token names from Zed's theme schema for consistency.

### Week 4 — signing, notarization, Sparkle
- Developer ID Application certificate in Keychain. `scripts/release.sh` produces a signed, notarized, stapled `.app` and DMG.
- `notarytool` pipeline working end-to-end with `keychain-profile`.
- Sparkle 2 integration via objc2 bridge (port `tauri-plugin-sparkle-updater`'s wrapper). Static `appcast.xml` on R2. Dummy v0.1.0 → v0.1.1 upgrade tested on a fresh user account.
- **Exit demo:** double-click `vish-v0.1.0.dmg` on a clean Mac, drag to Applications, launch. ⌥Space shows the panel. An hour later, v0.1.1 prompt appears. Click update, app relaunches on v0.1.1.

**What's deferred from Phase 1:** any search logic, any LLM calls, settings UI, onboarding flow, crash reporting. That's all Phase 2+.

---

## Phase 2 — Indexing daemon and universal launcher (10 weeks)

**Goal: `vishd` runs as a LaunchAgent, indexes apps + files + browser history + mail + messages + calendar + contacts, and the UI searches them with sub-50ms p95 latency.**

### Week 5–6 — daemon process and IPC
- `vishd` binary with LaunchAgent plist. Installed on first launch of `vish.app` into `~/Library/LaunchAgents/com.vish.indexer.plist`, `launchctl load` via the UI.
- Unix socket IPC at `~/Library/Application Support/vish/ipc.sock`. bincode, length-prefixed, handshake with version check. Schema in `vish-core/src/proto.rs`.
- FDA detection via EACCES probe on `~/Library/Safari/Bookmarks.plist`. Deep-link to System Settings on denial.
- Health/status endpoint; UI shows a menu bar dot (green = healthy, amber = indexing, red = error).

### Week 7 — tantivy + sqlite schema
- `vish-index` crate. SQLite migrations via `refinery`. Schema: one table per source plus a unified `documents` join view for search.
- tantivy index at `~/Library/Application Support/vish/tantivy/`. Schema: `id`, `source`, `title`, `body`, `path`, `timestamp`, `tags`. `STORED | INDEXED | TEXT` on body; `STRING` facets on source for filtering.
- Writer batches every 5s or 10k docs, whichever first. Committer is a dedicated thread with `tokio::sync::mpsc`.

### Week 8 — P1 sources (apps + files)
- Apps: walk `/Applications`, `/System/Applications`, `~/Applications`; parse `Info.plist` via the `plist` crate; extract icons with `icns`. Tests use fixture `.app` bundles in `crates/vish-sources/fixtures/apps/`.
- Files: `notify` v7 watcher on `$HOME` with excludes. Initial walk with `walkdir` + `ignore`. Content extraction deferred — index path + filename only. Persist `lastEventId`.
- UI: typing in the TextField sends `Search` over IPC; results stream back, rendered in `ResultList` with icons. Arrow keys navigate, Enter launches.
- **Exit:** ⌥Space, type "term", Terminal.app appears first result in <50ms. Type a filename, fuzzy matches appear.

### Week 9 — P2 sources, part 1 (browsers + calendar + contacts)
- Chrome/Arc/Brave: copy `History` + sidecars to tmp, open `?mode=ro&immutable=1`, convert Webkit timestamps. Handle the exclusive-lock-while-running case.
- Safari: direct read with `immutable=1`. Data vault handled by FDA.
- Firefox: `places.sqlite`, `moz_places` + `moz_historyvisits`, PRTime epoch.
- Calendar: `objc2-event-kit` EKEventStore, request access, enumerate events in a rolling ±1-year window, re-fetch daily.
- Contacts: `objc2-contacts` CNContactStore, full dump on initial, observe change notifications for deltas.

### Week 10–11 — P2 sources, part 2 (mail + messages)
- Mail: open `Envelope Index` read-only, `JOIN` subject/from/to/date. For body, locate `.emlx` on disk, strip the 4-byte length prefix and trailing plist, parse RFC822 with `mailparse`. Index incrementally by rowid.
- Messages: `chat.db` read-only. `JOIN message ON handle` for conversation context. `attributedBody` NSKeyedArchiver decoder ported from `imessage_tools`. Skip tapbacks and read receipts.
- Both sources use a 24-hour incremental re-scan cadence (FSEvents on these files is unreliable).

### Week 12 — embeddings + vector search + hybrid retrieval
- `vish-embed`: `fastembed-rs` wrapping ONNX Runtime, `bge-small-en-v1.5` (384-d). Batch size 32, pooled embedding.
- `sqlite-vec` extension loaded via `rusqlite::LoadExtensionGuard`. Schema: `embeddings(id, source, embedding BLOB)`. Brute-force KNN with metadata pre-filter.
- Background re-embedding worker: queue items after ingest, process at idle. Priority inversion safe (UI search always beats re-embed).
- Hybrid retrieval: BM25 from tantivy + cosine from sqlite-vec, fused via Reciprocal Rank Fusion (k=60). Exposed as a single `Search` IPC call with a `mode: {Lexical, Semantic, Hybrid}` field.

### Week 13–14 — polish, onboarding, stability
- First-run onboarding: TCC walkthrough (AX, FDA, Contacts, Calendar), source-picker for "what should I index", estimated initial-index time.
- Crash reporting via `sentry-rust` (self-hosted Sentry or GlitchTip, never a third party that sees user data — we anonymize paths before upload).
- Instruments profiling pass: no main-thread stalls >8ms during a 100k-result search.
- 1M-document stress test with synthetic mail corpus.
- **Exit demo:** fresh install, grant FDA, wait 20 minutes on a typical Mac (50k files, 10k emails, 30k messages). Type "sarah thesis defense" → top result is the actual conversation, in <80ms.

---

## Phase 3 — Local LLM chat with on-device RAG (10 weeks)

**Goal: the user can open a chat tab in the launcher, ask a question, and get a streaming answer from a local MLX model grounded in their own indexed data.**

### Week 15–16 — inference sidecar
- `vish-mlx`: bundled `uv`-managed Python venv at `Contents/Resources/mlx_sidecar/`. Install `mlx-lm` pinned to a specific version. `scripts/bootstrap-sidecar.sh` rebuilds it in CI.
- `mlx_lm.server` spawn manager: `std::process::Command` with stdio piped, waits for readiness on the HTTP endpoint (GET `/v1/models` returns 200), health-checks every 5s, auto-restarts on crash with exponential backoff.
- Sidecar listens on a Unix socket forwarded from an ephemeral localhost port (MLX server binds TCP only — we bridge).
- Entitlements updated for JIT + unsigned exec memory. Code-signing deep-signs the Python dylibs.

### Week 17 — Backend trait + OpenAI client
- `vish-llm/Backend` trait: `async fn chat_stream(&self, req: ChatRequest) -> impl Stream<Item = Result<ChatChunk, LlmError>>`.
- Implementations: `MlxLmServerBackend`, `OllamaBackend`, `AnthropicBackend` (cloud fallback). `reqwest` + `eventsource-stream` for SSE.
- Config: `~/Library/Application Support/vish/config.toml` with `[llm.default]` block specifying backend + model.

### Week 18–19 — chat UI
- New GPUI view: chat tab accessible via ⌘T inside the launcher panel. Message list with streaming renders. Markdown via `pulldown-cmark` + syntax highlighting via `tree-sitter-highlight`.
- Conversation persistence in SQLite (`conversations`, `messages` tables). Fuzzy-searchable from the launcher ("chat: how do I" finds past conversations).
- Model picker UI; download progress for new MLX models (pull from HF via `huggingface-hub` inside the sidecar).
- **Exit:** ⌥Space, ⌘T, ask "write me a haiku about debugging," get a streaming answer at ≥30 tok/s on Llama-3.1-8B-Q4 MLX on M3.

### Week 20–22 — RAG pipeline (the differentiated feature)
- `vish-llm/rag`: retrieval orchestrator. Takes a user query, routes through the indexer (hybrid search), chunks + re-ranks top-k results, constructs a system prompt with context.
- Citation UI: every sentence in the LLM's response that's grounded in retrieved context gets an inline citation chip. Clicking opens the source (mail in Mail.app, message in Messages, file in Finder).
- Prompt assembly: Jinja-like templates in `vish-llm/templates/` for different query types (factual lookup, summarization, conversation Q&A). Reuses the same templates across backends.
- Re-ranker: cross-encoder model (`bge-reranker-base`) via fastembed, runs on top-50 candidates, keeps top-8 for the context window. Configurable.
- **Exit demo:** "when did I last talk to Sarah about my thesis defense" → a paragraph citing three specific iMessages with dates and a calendar event, all linkable.

### Week 23–24 — stability, tuning, release v0.2
- Long-context stress test: 8K context on M1 Max — measure real TPS (expect degradation; mitigate with chunk size tuning).
- Fallback cascade: if local model fails or is too slow, prompt the user to fall back to a configured cloud model. Never silently call the cloud.
- Memory ceiling: kill and restart the sidecar if it exceeds a user-configured cap (default 12GB on 16GB machines, 32GB on 64GB+).
- **Release v0.2** — the first publicly usable version. Ship it.

---

## Phase 4 — Polish, extensions, agent features (3–6 months)

**Goal: vish is a product people pay for or adopt over Raycast. Beyond this phase, we are iterating on a shipped product.**

### Extensions system (6 weeks)
- Plugin-as-child-process protocol modeled on `pop-os/launcher`. Plugins are executables in any language speaking JSON-line over stdio.
- Plugin manifest: name, version, activation keywords, IPC schema. Installed to `~/Library/Application Support/vish/plugins/<id>/`.
- Sandbox boundary: plugins run without FDA, no IPC back to `vishd` directly. They request data via structured queries to the host.
- Starter plugins: calculator, unit converter, clipboard manager, snippet expander, GitHub issues, Linear tickets.

### Tool-using agent mode (4 weeks)
- LLM gains access to a `tools` registry: search own index, open file, launch app, compose email draft, create calendar event, run shell command (permission-gated).
- MCP server support as a cross-cutting integration — vish speaks MCP to external servers (GitHub, Slack, etc.) and exposes its own index as an MCP server to other agents.
- Multi-step planning with user approval checkpoints. No silent action execution.

### Advanced inference (4 weeks)
- Migrate primary backend to `mistral.rs` in-process if MoE Metal kernel lands (tracking Issue #2032).
- `llama-cpp-2` backend for GGUF compatibility — users can import models from their Ollama installation.
- Speculative decoding if the backend supports it.
- Evaluation harness: continuous quality regression tests on a held-out corpus of user-style queries.

### Continual learning experiment (research, timeline TBD)
- Given the author's continual-learning background: can per-user LoRA adapters, trained nightly on the user's corpus, meaningfully improve retrieval relevance and answer quality over static models? This is a research question that belongs in a paper, not a release. Treat as exploratory.

---

## What is explicitly out of scope for v1

These are recurring temptations. Do not do them.

- **Linux and Windows.** GPUI's non-Mac backends are too immature. The product thesis is Mac-native; going cross-platform dilutes it.
- **Team/sync features.** On-device is the moat. Cloud sync breaks the privacy story.
- **A web version.** Same reason.
- **Your own inference engine.** We integrate. MLX and llama.cpp are each the work of tens of engineers over years.
- **Porting `mlx-lm` to Rust.** 1–3 weeks of work, then a permanent maintenance tax for every new model family. Stay on the sidecar.
- **Voice input/output.** Whisper.cpp integration is a plausible v1.1; don't pull it into v1.
- **iOS companion.** Different product.

---

## Success criteria by phase

| Phase | Exit artifact | Hard measurable |
|---|---|---|
| 1 | Notarized DMG, Sparkle-updating | Hotkey → panel visible in <80ms p95 |
| 2 | Daemon indexes 7 sources | 1M-doc search <80ms p95 |
| 3 | Local MLX chat with RAG citations | ≥30 tok/s on Llama-3.1-8B-Q4 MLX, M3 |
| 4 | Extensions + agent mode | User-reported sessions/day as the north star |

## Known high-risk moments

- **Phase 1 week 4:** first notarization attempt almost always fails with an entitlements mismatch. Budget a full day.
- **Phase 2 week 11:** Messages `attributedBody` parsing has breaking changes between macOS versions. Test on at least Sonoma, Sequoia, and the current macOS.
- **Phase 3 week 15:** Python sidecar signing is finicky. Every `.so` in the venv needs to be either signed or excluded. Study how Ollama does it.
- **Phase 3 week 22:** RAG prompt engineering is where polish lives or dies. Budget 2× the coding time for iteration on templates and re-ranking thresholds.
- **Phase 4:** scope creep. Extensions and agents will each expand to fill the time given. Set hard deadlines and cut.

## When to re-plan

If a milestone slips by >2 weeks, stop and re-plan the phase. Do not absorb slippage silently — it compounds. If a technical assumption breaks (GPUI becomes unusable, `mlx-lm` removes the OpenAI server, TCC adds new scopes), re-plan the affected phase and update CLAUDE.md in the same week.

If two phases in a row slip by >2 weeks each, the product scope is wrong. Cut, don't push.
