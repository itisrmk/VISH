# ROADMAP.md — vish

> The 14-week solo execution plan to v1.0. Each phase has a single demo-able artifact and a hard performance gate. Slippage on a gate re-plans the phase, not the product.

## Guiding principles

**Speed is the feature.** Every phase ends with a measurement, not a demo. If the measurement misses the budget in CLAUDE.md §5, the phase is not done — even if everything works.

**Vertical slices, not horizontal layers.** Phase 1 ships a notarized `.app` that opens an empty window on ⌥Space. Phase 2 makes it launch apps. Phase 3 adds files. We never have a half-built layer cake of features.

**No premature abstraction.** Eight built-in sources is a small enough number that a `SearchSource` protocol is justified, not over-engineered. A plugin API is not justified until the eighth source has shipped and we have learned what they have in common. Defer.

**Profile every week.** A weekly `scripts/benchmark.sh` run that writes results to `benchmarks/YYYY-MM-DD.json` is part of the workflow, not a Phase 5 nice-to-have. Regressions caught at the week boundary cost a day; regressions caught at release cost a sprint.

---

## Phase 1 — Shell, hotkey, distribution pipeline (3 weeks)

**Goal: a notarized, signed, auto-updating `.app` that opens an empty styled NSPanel on ⌥Space, hides on Esc, lives in the menu bar. Nothing functional yet.**

### Week 1 — Xcode project and window
- Xcode 16 project with the directory layout from CLAUDE.md §4. Swift 6 strict concurrency on. macOS 14 deployment target. `LSUIElement = YES` in Info.plist.
- `MenuBarController` with `NSStatusItem` and a minimal "Quit" menu.
- `LauncherPanel` (`NSPanel` subclass) with `.nonactivating` style mask, `.floating` window level, `.canJoinAllSpaces | .fullScreenAuxiliary` collection behavior. NSVisualEffectView blur background. Rounded corners via layer.
- Window pre-warmed at app launch, parked at `(-10000, -10000)`, alpha 0.
- **Exit:** ⌘R from Xcode → menu bar icon appears within 200ms (we'll tighten in Phase 5). No window yet.

### Week 2 — hotkey and show/hide
- Add `KeyboardShortcuts` package via SwiftPM. Define `.toggleLauncher` shortcut with default ⌥Space. Wire to a `HotkeyController` that calls `LauncherPanel.show()` / `hide()`.
- `show()`: `makeFirstResponder` on the input field while still off-screen; `setFrame:` to centered position on the active screen; `orderFront:`; animate alpha 0→1 over 1 frame (16ms).
- `hide()`: animate alpha 1→0 over 1 frame; `orderOut:`; do not move the window back off-screen until the next show (avoids a measurable layout pass).
- Esc key handler in the panel hides the window.
- **Exit:** ⌥Space anywhere → blurred panel appears centered. Esc → it disappears. Test on a 120Hz display, confirm the appear animation is smooth.

### Week 3 — signing, notarization, Sparkle
- Developer ID Application certificate in Keychain. Hardened runtime in Build Settings. `--options runtime --timestamp` in the codesign step.
- `scripts/release.sh` does archive → codesign → DMG → `notarytool submit --wait` → `stapler staple`.
- Sparkle 2 added via SwiftPM. `SPUStandardUpdaterController` instantiated in `AppDelegate`. Static `appcast.xml` on Cloudflare R2.
- Test: install v1.0.0-beta.1 on a clean Mac, ship v1.0.0-beta.2, confirm the Sparkle prompt appears within an hour (or trigger manually via "Check for Updates").
- **Exit demo:** double-click `vish-1.0.0-beta.1.dmg` on a Mac that has never seen vish. Drag to Applications. Launch. ⌥Space shows the panel. An update to beta.2 prompts and applies. Cold launch measured at <200ms (we will tighten this in Phase 5).

**Deferred from Phase 1:** any actual search, Settings UI, onboarding, login-item registration. All Phase 5.

---

## Phase 2 — Apps, system actions, calculator (3 weeks)

**Goal: vish becomes a usable app launcher and command runner. Type "term" → Terminal launches. Type "lock" → screen locks. Type "2+2" → 4.**

### Week 4 — search infrastructure
- `SearchSource` protocol: `func search(_ query: String) -> AsyncStream<SearchResult>`.
- `SearchActor`: `TaskGroup` fan-out across enabled sources, cancellation on every new query.
- `Ranker`: weighted combination of source priority + per-source raw score + frecency bonus. `Frecency` table in SQLite via GRDB.
- `ResultsTableView`: NSTableView subclass with cell reuse. Custom `NSTableCellView` drawn programmatically — icon left, title + subtitle stacked, hotkey hint right. Selection follows arrow keys; Enter activates; ⌘1–9 jumps directly.
- `InputField`: NSTextField subclass overriding `keyDown:` to forward arrow keys, Enter, ⌘1–9, and Esc to the panel without losing focus.

### Week 5 — Apps source
- `Sources/Apps/AppCatalog.swift`: walk `/Applications`, `/System/Applications`, `~/Applications`, `/Applications/Utilities`. Parse `Info.plist` via `Bundle(url:)`. Extract `CFBundleName`, `CFBundleIdentifier`, icon path.
- Icons: load via `NSWorkspace.shared.icon(forFile:)`. Cache `NSImage` references in memory keyed by bundle ID. Lazy first-render only — initial scan stores paths only.
- Persist catalog to SQLite. On launch, load from SQLite synchronously (cached app catalog beats walking `/Applications` on cold start by ~70ms).
- FSEvents watcher on the four app directories — additions/removals trigger an incremental refresh on a background actor.
- `FuzzyMatcher`: Smith-Waterman variant. Bench: <1µs per (query, candidate) on 5000 candidates.
- In-memory `Trie` keyed on the prefix of every word in every app name (so "ps" matches "Photoshop" as well as "App Store" via "App").
- **Exit gate:** App-catalog search latency for top-8 results <2ms p99 in `XCTest` measure block on a 5000-app synthetic catalog.

### Week 6 — System Actions and Calculator
- `Sources/SystemActions/`: hardcoded list of 12 actions. Each is a struct with `id`, `title`, `subtitle`, `icon`, and an async `perform()` closure. Actions: Sleep, Lock Screen, Restart, Shutdown, Empty Trash, Show/Hide Hidden Files, Toggle Dark Mode, Eject All Volumes, Toggle Wi-Fi, Toggle Bluetooth, Toggle Do Not Disturb, Log Out.
- Implementations via the appropriate Apple APIs: `IOPMAssertion` and `pmset` for sleep/lock, `osascript` for restart/shutdown (with confirmation dialog), `NSWorkspace` for hidden files toggle, `CWWiFiClient` for Wi-Fi, `IOBluetooth` for Bluetooth, `NSWorkspace` notifications for DND status.
- `Sources/Calculator/`: hand-written recursive-descent parser. Tokens: number, +, -, *, /, %, ^, (, ). Returns `Double` or fails silently (no result rendered). Live evaluation on every keystroke; result rendered as a single special row with copy-on-Enter.
- **Exit demo:** ⌥Space, "term" → Terminal first hit, Enter launches. ⌥Space, "lock" → Lock Screen first hit, Enter locks the screen. ⌥Space, "(127*8)+45" → "1061" displayed, Enter copies to clipboard. Keystroke-to-result <16ms p95.

---

## Phase 3 — Files, URLs, web search (3 weeks)

**Goal: vish covers the everyday "find that PDF I downloaded yesterday" and "open this URL" cases. Feature parity with Alfred's free tier.**

### Week 7 — Spotlight integration
- `Sources/Spotlight/SpotlightSource.swift`: wraps `NSMetadataQuery` in an `AsyncStream`. Configures `predicate` from query string with sensible default scopes (`kMDItemContentTypeTree IN ['public.content', 'public.text', 'public.image']`).
- Live updates: enable `NSMetadataQueryDidUpdateNotification`, stream incremental result deltas (additions, removals, changes) into the table.
- Cancellation: `stop()` on the query when the wrapping `Task` is cancelled.
- Filters: `all:` prefix removes the content-type predicate. `kind:image`, `kind:doc`, `kind:code` add specific predicates. `from:appname` filters by `kMDItemKind`.
- Settings: optional full-disk file search opens the macOS Full Disk Access pane, builds a compact filename catalog fallback, and switches Spotlight to local-computer scope after the user opts in.
- **Exit gate:** Spotlight live query for top-20 results <30ms p95 across a representative `$HOME` (≥100k indexed items).

### Week 8 — URLs and Web Search
- `Sources/URLs/URLDetector.swift`: regex + heuristic to classify a query as URL-like. Handles bare domains (`apple.com`), schemed URLs (`https://...`), `localhost:port`, IPv4 literals. Result: "Open «url» in default browser."
- `Sources/Quicklinks/QuicklinkSource.swift`: user-defined keyword + URL template pairs for custom web searches. Examples: `gh react`, `yt swiftui`, `maps coffee`. `{query}` expands to the percent-encoded remaining input. Common defaults show built-in icons, and custom quicklinks can store user-uploaded icons.
- `Sources/WebSearch/WebSearchSource.swift`: low-priority fallback. Always returns one result for the current query: "Search «provider» for «query»". Provider configurable (Google, DuckDuckGo, Kagi, Bing). Selecting opens the provider URL in the default browser.
- Default-browser detection via `LSCopyDefaultApplicationURLForURL`. Cached at launch.
- Triggering rule: WebSearch only renders when no other source has returned a result with score >0.3 within 100ms. This avoids "Search Google for fina..." appearing while the user is still typing "finance.app".

### Week 9 — Frecency and ranking polish
- `Frecency` actor: every successful activation (Enter on a result) writes to `frecency(item_id, kind, last_used_at, use_count, score)`. Score = `use_count * exp(-Δt / half_life)` with half-life = 14 days, recomputed on read.
- Top-100 frecency rows cached in memory at launch and refreshed every 5 minutes.
- Ranker integrates frecency as a multiplicative bonus (1.0 + min(frecency_score, 5.0) * 0.1).
- Settings (basic SwiftUI window): per-source enable toggles, source priority sliders, hotkey rebinding, web search provider picker. No fancy onboarding — Phase 5.
- **Exit demo:** install fresh, use vish for an hour, observe that frequently-launched apps drift to the top of generic queries. Spotlight files appear within 30ms of typing a partial filename. Bare URLs are recognized and openable.

---

## Phase 4 — Clipboard, snippets, polish (3 weeks)

**Goal: the productivity-power-user features. Vish becomes sticky.**

### Week 10 — Clipboard history
- `ClipboardActor`: `Timer.publish(every: 1.0)` polling of `NSPasteboard.general.changeCount`. On change, capture all string types from the new content and the source application name (via `NSWorkspace.shared.frontmostApplication`).
- Storage: SQLite table `clipboard(id, content, content_type, source_app, captured_at)` with FTS5 virtual table on `content`. Cap at 100 entries; oldest evicted on insert.
- UI: dedicated hotkey (default ⌘⇧V) opens vish in clipboard mode — same panel, but pre-filtered to clipboard source. Up/down navigates history; Enter pastes (requires Accessibility permission for `CGEventPost`).
- Sensitive content guard: skip storage when `frontmostApplication` matches a denylist (Keychain Access, 1Password, Bitwarden, etc.) or when the pasteboard has the `org.nspasteboard.ConcealedType` UTI.

### Week 11 — Snippets
- `SnippetActor`: user-defined `;trigger → expansion` pairs. Storage: SQLite table `snippets(trigger, expansion, kind, created_at, last_used_at)` with FTS5 on `trigger`.
- Settings UI: Snippets tab with add/edit/delete, multi-line expansion, optional dynamic tokens (`{date}`, `{time}`, `{clipboard}`).
- Two activation paths: (1) typed inside vish with `;` prefix, expansion copied/pasted on Enter; (2) typed anywhere with text-expansion mode on (background `CGEventTap` watching for trigger sequences). Mode (2) is opt-in and clearly labeled because it requires Accessibility.
- Default snippets shipped: `;date`, `;time`, `;email` (user's email), `;sig` (user's signature).

### Week 12 — Result UI polish + accessibility
- Custom result row drawing: title with fuzzy-match highlights (matched characters bold), subtitle dimmed, source-type chip on the right, hotkey hint (⌘1–9) on far right.
- Universal Actions menu on Right Arrow / Command-/: files get Quick Look, reveal, copy path, and Open With; URLs get copy URL and Search Web; text/clipboard results get copy text and Save as Snippet. Action discovery must stay lazy and outside the keystroke path.
- Smooth scroll: scroll-to-row uses `NSAnimationContext` with 100ms easeOut for keyboard-driven selection movement past the visible window.
- VoiceOver: every result row gets an `accessibilityLabel` combining title, subtitle, and source. Input field labeled. Window labeled "vish launcher". Tested with VoiceOver on for one full session.
- Dark/light mode: all colors via `NSColor` system colors (no hardcoded hex). `NSImage` template images for monochrome icons.
- Localization scaffolding (English-only ships, but strings are extracted to `Localizable.strings` for later).
- **Exit gate:** `scripts/benchmark.sh` measures cold launch ≤120ms, hotkey-to-frame ≤16ms, keystroke-to-result ≤16ms p95 across all eight sources enabled. Idle CPU 0.0% in Activity Monitor over a 5-minute observation window. Idle RSS ≤80MB.

---

## Phase 5 — Onboarding, settings, v1.0 release (2 weeks)

**Goal: ship.**

### Week 13 — onboarding and Settings
- First-launch onboarding (SwiftUI window, not in hot path): three screens. (1) Welcome + hotkey rebind picker. (2) Permissions request walkthrough — Accessibility (only asked if user enabled clipboard paste or text expansion in screen 3), no FDA needed. (3) Feature pickers — which sources to enable, which to disable.
- Settings window (SwiftUI): General (hotkey, launch at login, appearance), Sources (enable/disable, priority sliders), Snippets (CRUD), Clipboard (history size, denylist), About (version, Sparkle update check, links).
- `LaunchAtLogin` (sindresorhus) integration. Off by default, enabled in onboarding.
- Crash log forwarding: only via the macOS-standard "Send to Apple" dialog. We do not ship a third-party crash reporter.

### Week 14 — release prep
- Marketing site (separate repo): single-page static site with download button, screenshots, GIF of cold launch + first search rendered in real time, and a clear "local-only, no telemetry, no cloud AI" statement. Hosted on Cloudflare Pages.
- Final `scripts/benchmark.sh` run on M1, M2, M3, M4 hardware (or as many as available). Results published in the marketing site as a "Benchmarks" section.
- Sparkle appcast on R2 with v1.0.0 release notes.
- App Store-style press kit (just in case): icon, screenshots, one-paragraph description, founder bio.
- Write a launch-day post explaining the design philosophy (single-axis discipline, performance budget, AppKit-first). Frame it for HN/lobste.rs/Mac dev Twitter.
- **Ship.**

---

## Out of scope for v1.0 (do not slip)

These are tempting and they are all wrong for v1.

- **Plugin/extension API.** Wait until the eighth built-in source has shipped and you've seen which patterns repeat. v2.
- **Sync across Macs.** Breaks the privacy story. v2 at earliest, and only if user demand is loud.
- **Window management.** Rectangle-style window snapping is a different product. No.
- **Workflows / multi-step automation.** Alfred's killer feature. We are not Alfred. Maybe v2.
- **Autonomous/cloud AI.** Local AI is allowed only through the scoped Phase AI plan. No cloud fallback, autonomous agents, background disk summarization, shell execution, or file mutation.
- **Voice input.** No.
- **iOS companion.** Different product entirely.

## Phase AI — Local assistant, after launcher budgets stay green

**Goal: add local AI where it helps without changing what makes vish fast. AI is explicit, local, source-backed, and measurable.**

### AI-0 — Bench and status
- `docs/AI_INTEGRATION.md` is the source of truth for scope and guardrails.
- `scripts/ai-benchmark.sh` measures Ollama chat first-token latency, tokens/sec, embeddings, and MemPalace search if installed.
- Settings shows local AI status only: Ollama reachable, installed models, selected model, MemPalace reachable. No AI search row yet.
- Exit gate: with AI disabled, existing `scripts/benchmark.sh` budgets are unchanged.

### AI-1 — Ask selected result
- Add Universal Actions: Ask AI, Summarize, Explain, Find Related, Save Answer as Snippet.
- Context is only the selected result plus capped previews. No broad disk reads.
- Stream the answer inline in the launcher lower pane, not in a separate window or result row.
- Exit gate: answer view opens immediately with a placeholder; warm first token <=1500ms on the selected default local model.
- Current status: Ask AI, Summarize, and Explain are implemented for apps, files, URLs/web/quicklinks, clipboard items, and snippets. Find Related and Save Answer as Snippet remain deferred.

### AI-2 — AI trigger
- Add `ai ` and `? ` intents. Basic explicit trigger path is implemented.
- Show one low-priority "Ask local AI" row only after fast results render. Current implementation returns the AI row directly for explicit AI intents and keeps it out of default search.
- Selecting the row opens the inline answer view and streams. Basic model-only answer streaming is implemented.
- Exit gate: trigger intent classification <=1ms and placeholder row <=16ms.

### AI-3 — Memory
- Add MemPalace search/write integration for approved transcripts, decisions, preferences, and scoped project/folder mining.
- Keep VISH's own file index as the filesystem retrieval layer.
- Exit gate: MemPalace top-5 warm search <=250ms.

### AI-4 — Safe tools
- Add constrained model tools: search files, read capped previews, search memory, search snippets, search clipboard, open/reveal/copy with confirmation where needed.
- No shell, no delete/move/rename/edit in the first AI release.
- Exit gate: every answer shows sources or is labeled model-only.

## Success criteria by phase

| Phase | Exit artifact | Hard performance gate |
|---|---|---|
| 1 | Notarized DMG, Sparkle-updating, empty window on ⌥Space | Cold launch <200ms (tightened to 120ms in P5) |
| 2 | Apps + System Actions + Calculator working | Keystroke-to-result <16ms p95 |
| 3 | Spotlight files + URL + Web fallback | Spotlight query <30ms p95 |
| 4 | Clipboard + Snippets + accessibility | Idle CPU 0.0%, idle RSS ≤80MB |
| 5 | v1.0 shipped, marketing live | All CLAUDE.md §5 budgets met simultaneously |
| AI | Local assistant, source-backed answers | No regression to Phase 5 budgets; warm first token ≤1500ms |

## Known risk moments

- **Week 3:** first notarization run almost always fails on entitlements. Budget a full day.
- **Week 5:** parsing weird app bundles (Electron apps with nested `.app`s, sandboxed apps with extra plists). Have a "skip and log" path, not a "crash and report bug" path.
- **Week 7:** `NSMetadataQuery` cancellation is subtle — it blocks if not stopped on the right run loop. Test cancellation aggressively.
- **Week 10:** clipboard polling is the only feature that touches `NSPasteboard.changeCount` continuously. Profile it. If it's not 0.0% CPU at idle, redesign.
- **Week 12:** the performance-budget exit gate is real. If a feature added in Weeks 4–11 has pushed any metric over budget, you find and fix it before declaring Phase 4 done. This is the moment most projects "decide later" and never recover.

## When to re-plan

If a phase slips by >1 week, re-plan that phase and write down what you learned in `LESSONS.md` (a new file, append-only). If two phases in a row slip, the scope is wrong — cut something explicitly, in writing, with rationale.

The whole point of this roadmap is that v1.0 is small enough that 14 weeks is realistic for a solo developer. If it stops being realistic, it is because scope crept in. Reread "Out of scope" above and remove whatever has crept.
