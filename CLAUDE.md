# CLAUDE.md — vish

> Read this at the start of every session. Single source of truth. Update it when decisions change. Do not duplicate its content elsewhere.

## 1. Project identity

**vish** is a native macOS launcher in the lineage of Alfred and Raycast. ⌥Space, type, Enter. It launches apps, opens files, performs system actions, evaluates calculator expressions, and routes everything else to web search or URL-open. It also has an opt-in local AI assistant for selected files, clipboard text, snippets, and memory-backed questions. It does not run on Linux or Windows. It is one binary, written in Swift, that opens its window in under one display frame and renders every keystroke at 120 Hz on ProMotion hardware.

The product thesis is **single-axis discipline: be the fastest launcher on macOS, by every measurable metric, on every supported chip.** Alfred is fast but dated. Raycast is feature-rich but ships heavy. There is room for a third option that wins on raw responsiveness and stays out of the user's way.

**Non-goals for v1.** No cloud AI. No autonomous agents. No background full-disk summarization. No shell execution through AI. No cloud sync. No team features. No mobile companion. No cross-platform. No plugin marketplace (we ship a fixed set of built-in capabilities; an extension API may come in v2). No App Store distribution (sandbox forbids the file-system reach we need; we ship Developer ID + notarized DMG).

## 2. Tech stack

Every choice is justified by the speed budget in §5. Substituting any of these requires updating both this file and the budget.

**Swift 6 with strict concurrency** (`-strict-concurrency=complete`). Targets macOS 14 (Sonoma) and later. We do not support older OSes — Swift 6 actor isolation, the modern `NSWindow` APIs, and the Spotlight live-query improvements are not worth giving up. macOS 14 covers the vast majority of in-use Macs by the time we ship.

**AppKit primary.** The popup window, the search field, and the result list are all AppKit. Specifically: `NSPanel` (not `NSWindow`) with `.nonactivating` style, a custom `NSTextField` subclass for the input, and `NSTableView` with cell reuse for the results. **SwiftUI is permitted only for the Settings window and onboarding flow** — surfaces where launch latency does not matter. The hot path is AppKit because SwiftUI's diffing has unpredictable cost at the 8ms-per-frame budget we need to hold.

**Spotlight (`NSMetadataQuery`) first for file search.** The system index is the preferred source because it is maintained for free and respects macOS metadata. VISH also keeps a compact filename catalog fallback for cases where Spotlight metadata is missing or unreliable for the user's home folders.
The fallback catalog is maintained with macOS FSEvents, not periodic rescans: 2s stream latency, 2s app debounce, persistent event IDs across launches, and full rebuild only when FSEvents reports dropped/coalesced/root-change events.

**SQLite via GRDB.swift** for our own catalog. Pinned major version. WAL mode. Migrations versioned in `vish/Storage/Migrations/`. We use FTS5 only for snippets and clipboard — apps and system actions are small enough that an in-memory `Trie` + fuzzy matcher beats any indexed query.

**KeyboardShortcuts (sindresorhus)** for the global hotkey, with a Settings UI for rebinding. Wraps Carbon `RegisterEventHotKey` — the same primitive Spotlight uses, the only one Apple has not deprecated for chord registration. Default ⌥Space (⌘Space collides with Spotlight).

**Sparkle 2** for auto-updates. Static appcast XML on Cloudflare R2. Standard updater controller, no custom UI.

**Ollama + MLX for local AI.** VISH talks to the local Ollama REST API only after the user invokes AI. On Apple Silicon, prefer Ollama's MLX-backed runtime when available. Do not embed a model server or Python runtime until profiling proves Ollama cannot meet the local AI budgets. Direct `mlx-lm` is a fallback path, not a parallel first implementation.

**MemPalace for AI memory.** VISH may integrate MemPalace for long-term local AI memory over conversations, decisions, preferences, and explicitly mined folders. VISH's own file index remains the fast filesystem retrieval layer. Do not mine the whole disk into AI memory by default.

**Sindresorhus suite** for the boring parts: `Defaults` for preferences, `LaunchAtLogin` for auto-start, `Settings` for the preferences window scaffolding. Battle-tested, narrow scope, no transitive dependency drama.

**No web view, anywhere.** No WKWebView, no Electron, no JS bridge. Every pixel is drawn by AppKit or Core Animation.

**No reactive frameworks.** No Combine in the hot path. No RxSwift. State changes flow through Swift `actor` isolation and `AsyncStream`. The result-list update path is hand-written, not framework-mediated.

## 3. Architecture

vish is **one process**. One menu-bar item, one hidden popup window, multiple actors inside.

```
vish.app
├── MainActor                     NSApp run loop, hotkey, NSPanel, views
├── CatalogActor                  app catalog, system actions, frecency
├── SearchActor                   query coordination, ranking, cancellation
├── SpotlightActor                NSMetadataQuery wrapper (file search)
├── ClipboardActor                NSPasteboard polling, history persistence
└── SnippetActor                  user-defined text expansions
```

Actors talk via `AsyncStream` for incremental results and `async` calls for one-shots. Every search is cancellable — pressing a key cancels the in-flight query before issuing the next. The MainActor never awaits a search directly; it subscribes to the SearchActor's stream and renders whatever arrives.

**The window is never destroyed.** It is created once at app launch, positioned off-screen at `(-10000, -10000)`, and `orderOut:` / `orderFront:` is used to show and hide. Closing the window is `orderOut:` only. Re-creating an `NSPanel` costs ~30ms; we cannot afford that on every hotkey press.

**The first character of input is captured before the window is visible.** When the hotkey fires, we (1) tell the input field to start receiving keystrokes via `makeFirstResponder:` on the off-screen window, (2) `orderFront:` on the same run-loop tick, (3) animate the alpha from 0 to 1 over one frame. Keystrokes that arrive during the show animation are not lost.

**No background daemon.** The app launches at login (LaunchAtLogin), runs as `LSUIElement = YES` (no Dock icon), and lives forever. Indexing the app catalog at login takes ~80ms on an M-series chip; we do it on a background queue while the menu-bar icon is already drawn.

## 4. Directory layout

Single Xcode project. SwiftPM for dependencies. No CocoaPods, no Carthage.

```
vish/
├── CLAUDE.md
├── ROADMAP.md
├── vish.xcodeproj
├── vish/                         # main app target
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   ├── MenuBarController.swift
│   │   └── HotkeyController.swift
│   ├── Window/
│   │   ├── LauncherPanel.swift   # NSPanel subclass
│   │   ├── InputField.swift      # NSTextField subclass
│   │   └── ResultsTableView.swift # NSTableView + delegate/datasource
│   ├── Search/
│   │   ├── SearchActor.swift
│   │   ├── Ranker.swift          # fuzzy + frecency
│   │   ├── FuzzyMatcher.swift
│   │   └── Result.swift
│   ├── Sources/
│   │   ├── Apps/
│   │   ├── SystemActions/
│   │   ├── Calculator/
│   │   ├── Spotlight/
│   │   ├── URLs/
│   │   ├── Quicklinks/
│   │   ├── WebSearch/
│   │   ├── Clipboard/
│   │   └── Snippets/
│   ├── Storage/
│   │   ├── Database.swift        # GRDB setup
│   │   ├── Migrations/
│   │   └── Frecency.swift
│   ├── Settings/                 # SwiftUI here, not in hot path
│   ├── Resources/
│   │   ├── Info.plist            # LSUIElement=YES
│   │   └── Assets.xcassets
│   └── vish.entitlements
├── vishTests/                    # XCTest
├── vishUITests/
└── scripts/
    ├── release.sh                # build + sign + notarize + staple
    ├── reset-tcc.sh
    └── benchmark.sh              # cold-launch + keystroke perf harness
```

If something doesn't fit one of these folders, name it properly and add a folder. Do not create a `Util/` or `Common/` dumping ground.

## 5. Performance budget — the heart of vish

These are not aspirations. They are pre-conditions for shipping a feature. A feature that violates them is not done, regardless of correctness.

| Metric | Budget | How measured |
|---|---|---|
| Cold launch (process start to menu bar icon visible) | ≤120 ms | `os_signpost` from `main()` to `NSStatusItem` first paint |
| Hotkey press to window first frame | ≤16 ms | Signpost from `KeyboardShortcuts` callback to `windowDidExpose` |
| Keystroke to first updated result rendered | ≤16 ms | Signpost from `controlTextDidChange:` to `NSTableView.didReload` |
| App-catalog search (top-8 results) | ≤2 ms | XCTest `measure` block |
| Spotlight file query (live, top-20) | ≤30 ms p95 | Signpost across `NSMetadataQuery` callbacks |
| Memory at idle | ≤80 MB RSS | Activity Monitor + `task_info` |
| Memory after 1 hour of use | ≤120 MB RSS | Same |
| CPU at idle | 0.0% (true idle, not "negligible") | Instruments Time Profiler |
| Frame drops during result-list scroll | 0 over 1000-row scroll | Instruments Animation Hitches |

The cold-launch budget is achievable because we (1) defer all indexing to after the menu bar icon is up, (2) load no XIBs (everything programmatic), (3) link only frameworks we actually use, (4) skip the launch-services dance for our own UI by being `LSUIElement`.

The keystroke budget is achievable because we (1) cancel the previous in-flight search on every character, (2) coalesce keystrokes that arrive within 8ms into a single search, (3) maintain a hot in-memory `Trie` for apps and system actions so the synchronous-fast path never touches SQLite or Spotlight, (4) update the table via `reloadData(forRowIndexes:columnIndexes:)` for changed rows only, never a full reload.

**Profile before claiming done.** Every PR that touches the hot path includes Instruments traces in the description. No "should be fast." Numbers or it didn't happen.

## 6. Search and ranking

The pipeline for every keystroke:

1. **MainActor** receives `controlTextDidChange:`, captures the new string, cancels the prior `Task`.
2. **SearchActor** receives the new query, fans out to all enabled Sources concurrently with `TaskGroup`.
3. Each Source returns a stream of `Result` values with a per-source raw score.
4. **Ranker** combines raw score with frecency signal (frequency × recency, classic Mozilla algorithm) and source priority weights.
5. **MainActor** subscribes to the ranked stream, applies a 16ms render coalescing window, updates the table.

Cancellation is structural: dropping the `Task` propagates `CancellationError` through every `await`, including into Spotlight's `NSMetadataQuery` (which we wrap to cancel via `stop()`).

**Fuzzy matching algorithm.** Smith-Waterman variant tuned for short queries against short strings (app names, action names). Single-pass, no allocations in the hot loop. Extracted into a `FuzzyMatcher` value type with `XCTest` benchmarks asserting <1µs per (query, candidate) pair on a 5k-candidate corpus.

**Frecency.** SQLite table `frecency(item_id, kind, last_used_at, use_count, score)`. Score recomputed on access using exponential decay (half-life: 14 days). Top-100 frecency entries cached in memory at launch, refreshed every 5 minutes from disk.

**Universal Actions.** Right Arrow / Command-/ opens a contextual menu for the selected result. Files expose Quick Look, reveal, copy path, and Open With; URLs expose copy URL and Search Web; text and clipboard results expose copy text and Save as Snippet. Action discovery is lazy and never participates in ranking or keystroke search.

**Local AI.** AI is trigger-based through `ai `, `? `, or Universal Actions on a selected result. It renders outside the result table after the fast path has completed. The model receives only tool-bounded context: ranked file metadata, capped text previews, snippets, clipboard items when enabled, and MemPalace memory results. The model never gets arbitrary filesystem access and cannot perform side effects without user confirmation.

**Source priority weights** are user-configurable in Settings but default to: System Actions 1.0, Apps 0.95, Frecency-Boosted Files 0.85, Calculator 0.80 (when query parses as expression), Quicklinks 0.78, URLs 0.75, Snippets 0.70, Clipboard 0.65, Spotlight Files 0.60, Web Search 0.10 (always last).

## 7. Data sources (v1 surface area)

Nine sources ship in v1. Each lives in `vish/Sources/<n>/`; hot-path sources keep lookup first-party and allocation-conscious.

| Source | What it does | Storage | Init cost |
|---|---|---|---|
| Apps | Indexes `/Applications`, `/System/Applications`, `~/Applications`, `/Applications/Utilities`. Parses `Info.plist` for name/bundle ID/icon path. Watches with FSEvents for additions/removals. | SQLite + in-memory Trie | ~80ms cold, instant warm |
| System Actions | Hardcoded list: Sleep, Lock Screen, Restart, Shutdown, Empty Trash, Show Hidden Files, Toggle Dark Mode, Eject All, Toggle Wi-Fi, Toggle Bluetooth, Toggle Do Not Disturb. | None | 0 |
| Calculator | Live expression evaluation as you type. Hand-written recursive-descent parser, not `NSExpression` (which crashes on malformed input). Supports +, -, *, /, %, ^, parens, unary minus. Unit conversion deferred to v1.1. | None | 0 |
| Files | Live `NSMetadataQuery` first, compact persisted filename catalog fallback. Scope: user folders by default; local computer/user volumes when full-disk mode is enabled. Filters to documents, folders, code, images, PDFs by default; everything via `all:` prefix. | Spotlight + JSON fallback | Background scan |
| URLs | Detects when the query is a URL (with or without scheme), offers Open. Handles `localhost:port` and IP literals. | None | 0 |
| Quicklinks | User-defined keyword + URL template pairs for custom web searches, e.g. `gh react`, `yt swiftui`, `maps coffee`. Uses `{query}` as the encoded query placeholder. Built-in icons cover common defaults; custom entries can store a user-uploaded icon. | Binary plist + in-memory keyword dictionary | ~1ms warm |
| Web Search | Fallback "Search Google for «query»" / "Search DuckDuckGo for «query»" when no other source returns ≥1 result. Provider configurable. | None | 0 |
| Clipboard | Polls `NSPasteboard` at 1 Hz on a background queue; stores last 100 string entries with timestamp and source app. Triggered by `clip ` prefix or via dedicated hotkey. | SQLite + FTS5 | ~5ms cold |
| Snippets | User-defined `;trigger → expansion` pairs. Triggered by typing the trigger anywhere when "Text Expansion" mode is on. | SQLite + FTS5 | ~5ms cold |

## 8. Permissions, signing, distribution

**TCC permissions.**
- **Accessibility** — required only for paste-on-select (text expansion, clipboard paste). Probe with `AXIsProcessTrustedWithOptions(prompt: false)`. Prompt only when the user enables a feature that needs it.
- **Full Disk Access** — optional. Default file search stays in the user home folder. If the user enables full-disk mode, vish opens the macOS Full Disk Access pane and then queries Spotlight with local-computer scope; macOS still requires the user to grant access manually.
- **Automation** — only if AppleScript bridges are added (deferred).

**Entitlements.** `com.apple.security.cs.allow-jit` and `com.apple.security.cs.allow-unsigned-executable-memory` are not needed in v1. The entitlements file is essentially empty — just `com.apple.security.network.client` for web search and Sparkle.

**Signing.** Developer ID Application certificate, hardened runtime, timestamped. `notarytool submit --wait` on every release build (never `altool`, dead since 2023). `stapler staple` both the `.app` and the `.dmg`.

**Distribution.** Direct DMG download from a static site. Sparkle handles updates.

**Local dev.** Stable ad-hoc signing identity to keep TCC permissions persistent across rebuilds. `scripts/reset-tcc.sh` calls `tccutil reset All com.vish.app`.

## 9. Coding conventions

**Swift 6, strict concurrency complete.** No `@unchecked Sendable` without a comment justifying it. No `@MainActor` on data types — only on UI controllers.

**Actor isolation, not locks.** If you find yourself reaching for `NSLock` or `DispatchQueue.sync`, the design is wrong. Restructure as an actor.

**No force-unwrap outside tests and one-time startup.** `guard let ... else { fatalError("explanatory message") }` at startup is fine. `!` in feature code is a bug.

**Errors are typed.** `enum SearchError: Error` per source. No `Error` thrown from a public API without a typed wrapper.

**Logging via `os.Logger`**, not `print`. Every subsystem has a static `Logger` with a category. Signposts (`os_signpost`) for every operation in the performance budget.

**No third-party dependencies in the hot path.** GRDB is fine (it's used outside the keystroke loop). KeyboardShortcuts is fine (its callback is the entry point, not hot). Anything in `Search/` or `Window/` is first-party.

**Programmatic UI only.** No XIBs, no Storyboards. They cost startup time and obscure the layout.

**SwiftFormat + SwiftLint** in CI. Pre-commit hook runs both.

**Tests.** XCTest. Performance-critical functions get `measure { }` blocks asserting absolute thresholds. Snapshot tests are banned (they break on every macOS release and obscure real regressions).

## 10. Build and release

**Dev:** press ⌘R in Xcode. Or:
```
xcodebuild -scheme vish -configuration Debug
```

**Release:**
```
./scripts/release.sh 1.0.0
# → xcodebuild archive
# → codesign with Developer ID, hardened runtime, --options runtime --timestamp
# → xcrun notarytool submit dist/vish-1.0.0.dmg --keychain-profile AC_PROFILE --wait
# → xcrun stapler staple dist/vish-1.0.0.dmg
# → upload DMG and appcast.xml to R2
```

`AC_PROFILE` set up once via `xcrun notarytool store-credentials`. Never commit App Store Connect API keys.

**Versioning.** SemVer. `CFBundleShortVersionString` and `CFBundleVersion` updated together. `appcast.xml` `sparkle:version` matches `CFBundleVersion`.

## 11. Non-negotiable invariants

If you (Claude Code) are about to violate one of these, stop and ask. These are the bugs that take a week to diagnose.

1. **Cold launch ≤120ms.** Every framework link, every `NSImage` load, every disk read at startup must be justified.
2. **Hotkey-to-frame ≤16ms.** The window is pre-warmed and never destroyed.
3. **Keystroke-to-result ≤16ms.** Searches are cancellable. The hot path doesn't allocate.
4. **AppKit on the main thread, always.** Use `MainActor` for UI controllers. Never reach into AppKit from a background actor.
5. **No SwiftUI in `Window/`, `Search/`, or `Sources/`.** Settings and onboarding only.
6. **No XIBs, ever.**
7. **The launcher window is created once and never destroyed.**
8. **Every search is cancellable.** Every long-running operation respects `Task.checkCancellation()`.
9. **No third-party dependencies in the hot path.** Anything new requires a written justification and a measured before/after.
10. **Profile before claiming done.** Instruments traces in the PR description for any hot-path change.
11. **No telemetry of any kind in v1.** The product's value is that it stays out of the user's way; that includes not phoning home.

## 12. When you (Claude Code) are uncertain

Stop and ask. If a task ambiguity touches the performance budget, default to the option that holds the budget even if it means more code. If a Swift 6 concurrency error feels like it wants `@unchecked Sendable`, the design is wrong — restructure first.

If a decision being introduced isn't covered above, update CLAUDE.md in the same commit. Documentation that drifts behind reality is worse than no documentation.
