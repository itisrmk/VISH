# AGENTS.md — vish

## Source of truth

Read `CLAUDE.md` and `ROADMAP.md` before changing code. Do not duplicate product, architecture, or roadmap decisions here; update those files when decisions change.
Read `log.md` before implementation work. It records the current handoff state, what has already been built, latest benchmark numbers, and known gaps.

## Execution rules

- Build the product described in `CLAUDE.md`: one native macOS Swift/AppKit app, no daemon, no cloud AI, no web view, no cross-platform code.
- Implement roadmap phases as vertical slices. Start with the smallest measurable artifact for the current phase.
- Keep hot-path code first-party, allocation-conscious, cancellable, and main-thread safe. Do not add abstractions until two real call sites require them.
- Use AppKit for launcher window, input, and results. SwiftUI is allowed only for Settings and onboarding.
- Keep the launcher panel pre-warmed; never destroy and recreate it on hotkey.
- Do not add dependencies to `Window/`, `Search/`, or `Sources/` without a written performance reason in `CLAUDE.md`.
- Prefer typed errors and `os.Logger`; do not use `print` in app code.
- Avoid force unwraps outside tests and one-time startup with a specific `fatalError`/`expect` reason.
- Profile before claiming any hot-path work is done. For now, at minimum run the relevant build/test command and state what was not measured.

## Local commands

- Generate the Xcode project: `xcodegen generate`
- Build: `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Benchmark: `./scripts/benchmark.sh`
- AI benchmark: `./scripts/ai-benchmark.sh`
- Signpost report from an Instruments trace/export: `scripts/signpost-report.sh <trace.trace|export.xml> [xpath]`
- Package release DMG: `scripts/release.sh <version>`; notarization runs only when `AC_PROFILE` is set. Sparkle release builds can pass `SPARKLE_FEED_URL`, `SPARKLE_PUBLIC_ED_KEY`, and optional `SPARKLE_GENERATE_APPCAST`.

## Current state - 2026-04-27

- Active implementation is the native Swift/AppKit app under `vish/` with the Xcode project `vish.xcodeproj`.
- Active optimization tasks are tracked in `docs/OPTIMIZATION_TASKS.md`; keep that checklist current when doing performance batches.
- Production UX and release gates are tracked in `docs/PRODUCTION_READINESS.md`; keep it current when changing Settings, onboarding, benchmarks, or release flow.
- The legacy Rust/GPUI workspace is not the active product path. Do not restore it or mix it back in unless the user explicitly requests that.
- The launcher UI is AppKit-only and prewarmed. SwiftUI is used only for Settings.
- Settings are lazily created; do not make Settings or indexing load eagerly at startup.
- File search uses Spotlight first and a compact fallback filename catalog. AI file finder keeps the launcher hot path safe by doing rank fusion across bounded candidates, then reading tiny previews off the main thread. Explicit AI file-finder queries can add local Ollama embedding reranking through a cached vector store; default search never invokes embeddings, and interactive queries do not write file vectors.
- File fallback maintenance is event-driven through FSEvents: 2s stream latency, 2s app debounce, persistent event IDs, and no periodic full rescan unless FSEvents reports dropped/coalesced/root-change events.
- FSEvents callback isolation crash is fixed; the stream callback and debounce now stay on the main dispatch queue, with index mutation still detached to utility work. The Release app was verified running past the 30s watcher startup delay.
- Default search is two-phase: render fast local results first, then merge file/Spotlight results only as a supplemental update.
- App search uses a small token/acronym/shortcut candidate index before fuzzy scoring.
- Tab locks the selected result into inline action mode; Command-/ is a secondary shortcut. Do not use popup menus for launcher actions. Keep actions lazy and out of search ranking: Ask AI/custom AI question, Quick Look, reveal, copy path/URL/text/name, Open With, Save as Snippet, Search Web, and the result primary action.
- Rich result UX is tracked in `docs/RICH_EXPERIENCE_TASKS.md`. V1 is implemented with a delayed 160 ms selection preview pane, `Command-Y` Quick Look, `Command-I` detail mode, `Command-B` in-memory file buffer, bounded rich previews including off-main image thumbnails, and local action-history ranking for Tab actions. Result rows still render before any preview work.
- Local AI is opt-in and trigger-based only. Follow `docs/AI_INTEGRATION.md`: Ollama local API first, MLX acceleration when available, MemPalace for explicit long-term memory, no startup probing, no default-search blocking, no arbitrary filesystem/tool access.
- Local AI chat streams pass through `AIStreamSanitizer` before UI append. Keep this boundary intact: no `<think>` tags, hidden reasoning, prompt text, or scratchpad output should reach `AIInlineAnswerView`.
- AI-0 is implemented, AI-1 has selected-result inline actions for `Ask AI`, `Summarize`, `Explain`, and typed custom questions after Tab-locking a result. AI-2 has a minimal trigger path: `ai <question>` and `? <question>` return one AI row, then stream inline inside the launcher lower pane through Ollama. AI file finder is implemented for `ai find/search/locate/show me ...` and `? find/search ...`: exact empty commands like `ai find` are claimed by semantic file mode and show a file-search prompt instead of falling through to chat. It parses type/date intent, uses the VISH file index plus Spotlight name/content search, reads capped text/PDF previews only for the shortlist, then fuses local Ollama embedding similarity from `Application Support/vish/file-vectors.plist`. Settings > AI has a version-gated curated chat model picker. On Ollama versions before 0.19 it offers `qwen3:4b` recommended, `qwen3:8b` quality, and `llama3.2:3b` fast. On Ollama 0.19+ it can offer `qwen3.5:4b`, `qwen3.5:9b`, and the 35B MLX model only on 32GB+ Macs. Settings > Files > Warm builds vectors only with a dedicated embedding model, skips unchanged vectors, batches background work, and pauses while the launcher is active. Settings > AI can install/select `embeddinggemma`; do not fall back to a chat model for full vector indexing. Selected-result AI uses only the chosen result plus capped previews; MemPalace integration, citations UI, Find Related, Save Answer as Snippet, automatic idle vector ingestion, and tool loops are not implemented yet.
- Settings > AI shows all compatible curated model choices, but checks actual immediately available disk capacity before enabling install. Low-disk missing models show a `Needs <N> GB free` subtitle and disabled install state; already-installed models stay selectable. Do not use purgeable/important-usage capacity for Ollama pull budgeting.
- Quicklinks are implemented as keyword + URL template pairs with `{query}` expansion, binary plist storage at `Application Support/vish/quicklinks.plist`, default `gh`, `yt`, and `maps` entries, built-in icons for common defaults, optional user-uploaded PNG-normalized custom icons, and a compact Settings pane.
- Clipboard history is opt-in, text-only, and trigger-based through `clip` / `clipboard`; it does not run in default search.
- The clipboard monitor polls `NSPasteboard.changeCount` only while enabled, stores at most 100 text entries, skips entries above 50k characters, and persists to `Application Support/vish/clipboard.plist`.
- Clipboard selection always copies the value; it sends Command-V only when macOS Accessibility trust is already granted.
- Snippets are implemented as `;`-triggered results with binary plist storage at `Application Support/vish/snippets.plist`, dynamic `{date}`, `{time}`, and `{clipboard}` tokens, compact CRUD in Settings, clickable token insertion, and starter templates.
- Result rows must not synchronously load uncached file/app icons during configuration; use placeholders, bounded cache, and utility-priority async fill.
- Result rows include source chips, command-number hints, animated keyboard scroll, and VoiceOver labels/help. Keep row chip layout responsive because the preview split can narrow the result column; chips and command hints must never overlap title/subtitle text.
- Current UI preferences: appearance System/Dark/Light, text size Regular/Large, bounded launcher size, draggable launcher position, rounded or sharp corners, web provider, quicklinks, clipboard history, and snippets.
- The launcher's normal search input intentionally has no placeholder text; keep the field visually blank on launch while preserving focus. Action mode may still use contextual placeholder text.
- Settings uses a minimal SwiftUI control-deck layout with a left section rail, neutral graphite background, iOS-style glass switches, and a single iOS-blue accent palette; avoid explanatory text density and keep it out of the launcher hot path. The default pane is Setup, which shows compact readiness cards for Launcher, Files, Clipboard, and AI plus the top production performance budgets.
- First-run onboarding is implemented in SwiftUI only, gated by `onboarding.completed`, shown after `ColdLaunchReady`, and reopenable from the menu bar through `Getting Started...`. The flow is value -> permissions -> feature defaults -> ready, and optional permissions/features must stay skippable.
- Do not reintroduce the previous green Settings accent, multicolor Settings accent gradients, or default checkbox toggles.
- Launcher panel defaults to 704 x 68 collapsed and 704 x 344 expanded, supports a bounded 86%-118% size scale, and persists a clamped top-left anchor when the user drags it.
- Sparkle 2.9.1 is linked by SwiftPM, but `UpdateController` only starts Sparkle when `SUFeedURL` and `SUPublicEDKey` are configured through release build settings.
- Latest passing Release smoke benchmark from `benchmarks/2026-04-27.json`: `launch_to_pid_ms: 107`, `idle_rss_kb: 75296`, `idle_cpu_percent_average: 0.0`.
- Latest passing AI benchmark from `benchmarks/ai-2026-04-26.json`: selected chat `qwen3:4b`, warm first token `103 ms`, warm tokens/sec `33.23`, selected embedding `embeddinggemma`, warm 8-document embedding `116 ms`.
- Last verified validation commands: `xcodegen generate`, `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`, `./scripts/benchmark.sh`, and `./scripts/ai-benchmark.sh`.
- Latest visual smoke: Option-Space, type `term`; Terminal appears as first result.

## Next priorities

- Validate launcher and Settings visually from screenshots before claiming UI work is done.
- Use Instruments or signpost analysis with `scripts/signpost-report.sh` for hotkey-to-frame, keystroke-to-render, and Spotlight p95 before claiming performance-budget completion.
- Finish missing v1 surfaces: Developer ID/notarized release credentials, hosted Sparkle appcast, and a full VoiceOver session.
- Keep UI customization simple. Prefer small typed preferences over a full theme editor until the core product is stable.

## Stop conditions

Stop and ask before violating the performance budget, adding a runtime dependency, introducing SwiftUI into the launcher hot path, restoring deleted legacy Rust code, or making destructive git changes.
