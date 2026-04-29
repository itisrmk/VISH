# vish Implementation Log

## 2026-04-25

### Current Direction

- Pivoted the active product to one native macOS Swift/AppKit app.
- The launcher hot path is AppKit: `NSPanel`, `NSVisualEffectView`, `NSTextField`, and `NSTableView`.
- SwiftUI is used only for Settings, which is lazily created after startup.
- The old Rust/GPUI implementation is not the active path. Do not restore it unless explicitly requested.

### Core Launcher

- Created a resident menu-bar macOS app with `LSUIElement` behavior.
- Added global hotkey support through `KeyboardShortcuts`; default is Option-Space.
- Kept the launcher panel prewarmed and reused with `orderFront` / `orderOut`.
- Added Escape handling to dismiss the launcher.
- Fixed typing focus so launching and immediately typing registers input.
- Added Enter activation, arrow selection, Command-1 through Command-9 direct activation, Command-Enter reveal, Control-Enter web search, and Tab inline action mode.
- Added Command-, from the launcher to open Settings.

### Launcher UI

- Replaced the large initial panel with a minimal collapsed rectangular search bar.
- Made the panel expand only when the user types.
- Added frosted material styling with border, blur, and simple dark/light/system support.
- Added user controls for launcher appearance: System, Dark, Light.
- Reintroduced launcher size customization as a bounded scale only, keeping the stable layout proportions.
- Added user controls for text size: Regular, Large.
- Added user control for rounded versus sharp launcher corners.
- Kept the launcher styling AppKit-only so search performance does not depend on SwiftUI.
- Added app and file icons through `NSWorkspace` with a small icon cache.
- Fixed a layout regression from earlier dynamic sizing where expanded results could cover or displace the search field. Current sizing is bounded to 86%-118% around the stable 704 x 68 collapsed and 704 x 344 expanded default.
- Added background dragging for the launcher panel; it persists a clamped top-left anchor so future launches reopen at the user's chosen screen position.

### Settings UI

- Added a lazily-created SwiftUI Settings window.
- Restyled Settings into card-style sections instead of a plain grouped form.
- Added controls for hotkey, appearance, window size, text size, corner style, web provider, and full-disk indexing.
- Added a Help section with the current command shortcuts.
- Added Full Disk Access helper buttons: open macOS Full Disk Access settings and reveal the vish app.
- Added indexing state with phase, percentage, progress bar, and indexed/scanned item counts.

### Search And Actions

- Added app search from `/Applications`, `/System/Applications`, `~/Applications`, `/Applications/Utilities`, and `/System/Applications/Utilities`.
- Added app catalog refresh and filesystem watcher for application folders.
- Added a compact app-search candidate index using token prefixes, acronyms, and two-letter shortcuts before fuzzy scoring.
- Added calculator parsing for `+`, `-`, `*`, `/`, `%`, `^`, parentheses, and unary signs.
- Added URL detection for schemed URLs, bare domains, localhost, and IPv4.
- Added configurable web search providers: Google, DuckDuckGo, Kagi, and Bing.
- Added system actions: Toggle Dark Mode, Lock Screen, Sleep, Show Hidden Files, Hide Hidden Files, Empty Trash, Eject External Disks, Log Out, Restart, and Shut Down.
- Added confirmation dialogs before destructive actions: Empty Trash, Log Out, Restart, and Shut Down.
- Added file actions: open, reveal in Finder, and copy path.
- Added URL actions: open and copy URL.
- Expanded Tab inline action mode for files, URLs, text, clipboard, and snippets: primary action, Quick Look, reveal, copy path/URL/text/name, Open With, Save as Snippet, Search Web, and selected-result AI.
- Added Quicklinks / Custom Web Searches with keyword + URL template matching, default `gh`, `yt`, and `maps` entries, `{query}` expansion, binary plist storage, built-in icons for common defaults, custom icon upload, and Settings CRUD.
- Added opt-in Clipboard History with `clip` / `clipboard` triggers.
- Clipboard entries are text-only, bounded to 100 items, capped at 50k characters per item, deduped by stable hash, and persisted as a binary plist.
- Selecting a clipboard result copies the value and only attempts Command-V when macOS Accessibility trust already exists.
- Added Snippets with `;` triggers, binary plist storage, default `;date`, `;time`, and `;clip`, and dynamic `{date}`, `{time}`, and `{clipboard}` expansion tokens.
- Snippet activation copies and pastes through the same Accessibility-gated paste path as Clipboard History.
- Made Snippet creation discoverable with clickable token chips, starter templates, a saved-snippet section label, and cheatsheet chips for `{date}`, `{time}`, and `{clipboard}`.
- Defined the local AI direction: opt-in Ollama + MLX runtime, MemPalace-backed memory for approved content, explicit `ai ` / `? ` triggers, selected-result Universal Actions, and strict separation from default launcher search.
- Added a minimal Local AI Settings pane with an opt-in toggle, Ollama base URL, model picker, and manual status check. It only probes Ollama from Settings.
- Added the first AI launcher path: `ai <question>` and `? <question>` now produce a single AI result, and Return streams the answer from the selected Ollama model in a separate AppKit panel.
- Kept AI out of default search ranking and persistence; the trigger path is explicit and not stored in frecency.
- Replaced the separate AI answer window with a compact inline answer view inside the launcher lower pane. The input stays active, Escape still hides the launcher, and typing a new query cancels the in-flight AI stream.

### File Search And Indexing

- Added Alfred-style file triggers: leading space, `'`, `open`, `find`, `in`, `tags`, `all:`, `kind:image`, `kind:doc`, and `kind:code`.
- Uses Spotlight first for live file lookup.
- Added compact fallback filename catalog for file-name search.
- Added optional full-disk mode that switches Spotlight scope to local computer.
- Added background file scan with real progress updates.
- Kept default search two-phase: fast local results render first, then file/Spotlight results merge in as a supplemental update.
- Avoided first-query fallback catalog loads; the file plist is only used after explicit warm/rebuild or prewarm.
- Throttled indexing progress updates and paused scanner work while the launcher is active.
- Added FSEvents-based file catalog maintenance for add/delete/rename changes: 2s stream latency, 2s app debounce, persistent event IDs, incremental batch updates, and full rebuild only on dropped/coalesced/root-change event signals.
- Fixed the FSEvents callback crash by moving the callback out of the MainActor-isolated watcher method; the callback now runs on the FSEvents queue and hops to MainActor only for watcher state delivery.
- Added directory skip rules for noisy/generated paths like caches, DerivedData, node_modules, Pods, target, and `.build`.

### Performance And Storage

- Added `os_signpost` probes for process launch, hotkey-to-frame, keystroke-to-render, search, and Spotlight query timing.
- Moved hotkey and keystroke signpost endpoints closer to actual window/table display completion.
- Added `scripts/signpost-report.sh` to summarize p50/p95 for vish signposts from an Instruments trace or exported XML.
- Added an 8 ms keystroke coalescing delay to avoid stale search work during fast typing.
- Added cancellation checks around search work and file lookup.
- Deferred uncached app/file icon loading out of result-row configuration; rows now render placeholders first and fill cached icons asynchronously.
- Reduced result-list reload work by reloading changed rows when the result count stays stable.
- Added source chips, stronger VoiceOver labels/help, and animated keyboard scroll for result rows.
- Removed eager Settings creation from startup.
- Removed eager file-index prewarm from startup to reduce idle memory.
- Kept Clipboard History out of default search and disabled by default; the pasteboard monitor only runs when enabled and only reads text after `NSPasteboard.changeCount` changes.
- Switched app catalog, frecency, and file catalog persistence to binary property lists with JSON fallback.
- Added `scripts/benchmark.sh` for Release smoke benchmarks with launch timing, RSS, CPU, architecture, and budget status.
- Added `scripts/release.sh` for archive, DMG packaging, and optional notarization/stapling when `AC_PROFILE` is set.
- Added `scripts/ai-benchmark.sh` to measure Ollama chat first-token latency, tokens/sec, embeddings, and MemPalace warm search when available.

### Settings UI

- Added first-run onboarding in SwiftUI with three compact steps: hotkey setup, permissions, and feature defaults.
- Onboarding is gated by `onboarding.completed`, appears only after the cold-launch readiness signpost, and can be reopened from the menu bar through `Getting Started...`.
- Replaced the generic vertical settings-card stack with a compact custom control deck: left section rail, right active pane, command-grid help, and a launcher preview.
- Reduced Settings text density: removed pane summaries, sidebar status text, control subtitles, and converted help into short command chips.
- Added a minimal Clipboard toggle, Accessibility Access button, and Clear action to the Search pane.
- Reworked Settings toward the iOS/macOS 26 Liquid Glass direction: translucent cards, iOS-style switch toggles instead of checkbox toggles, no green accent, and a single iOS-blue palette in the logo and active controls.
- Simplified the Settings palette again to remove blue/rose/orange accent competition; Settings now uses one iOS-blue family plus neutral glass surfaces.
- Removed the blue Settings background gradient/glows; the background is now neutral graphite with subtle non-blue depth.
- Added a minimal Launcher Size slider with percentage readout and a Center action to clear the saved launcher position.
- Added a compact Snippets pane for add/edit/delete and an About pane with version and update check.
- Added a compact Quicklinks pane with keyword/name/template editing, `{query}` insertion, starter chips, and saved quicklink list.
- Kept Settings in SwiftUI only; no SwiftUI was added to the launcher hot path.
- Updated the Settings window to a transparent full-size-content chrome sized at 680 x 500.

### Release And Updates

- Added Sparkle 2.9.1 via SwiftPM and a gated `UpdateController`; Sparkle only starts when release builds provide `SUFeedURL` and `SUPublicEDKey`.
- Added Check for Updates actions in the menu bar and Settings About pane.
- Extended `scripts/release.sh` to inject Sparkle feed/key build settings and optionally run a Sparkle appcast generator through `SPARKLE_GENERATE_APPCAST`.
- Verified local archive and DMG creation without notarization credentials:
  `scripts/release.sh 0.1.0-local`

### Verification

- Debug build passed:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release build passed after the FSEvents crash fix:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Release build passed after the Settings redesign:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Release build passed after the minimal Settings text pass:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Debug build passed after Clipboard History:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Debug build passed after the Settings Liquid Glass / switch redesign:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Debug build passed after simplifying Settings to one iOS-blue palette:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Debug build passed after removing the blue Settings background gradient:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Debug build passed after adding draggable launcher position and bounded launcher sizing:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Debug build passed after Snippets, result accessibility polish, and Sparkle integration:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Debug build passed after adding snippet token discovery and starter templates:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Debug build passed after first-run onboarding:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release build passed after first-run onboarding:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Relaunched the updated Release app after first-run onboarding.
- Release build passed after adding snippet token discovery and starter templates:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Relaunched the updated Release app for testing after snippet token discovery.
- Release smoke benchmark passed after Snippets, result accessibility polish, and Sparkle integration on 2026-04-25:
  `launch_to_pid_ms: 101`
  `idle_rss_kb: 51520`
  `idle_cpu_percent_average: 0.0`
- Local release DMG creation passed after Sparkle release-script wiring:
  `dist/vish-0.1.0-local.dmg`
- Release smoke benchmark passed after adding draggable launcher position and bounded launcher sizing on 2026-04-25:
  `launch_to_pid_ms: 97`
  `idle_rss_kb: 53056`
  `idle_cpu_percent_average: 0.0`
- Release smoke benchmark passed after the Settings Liquid Glass / switch redesign on 2026-04-25:
  `launch_to_pid_ms: 96`
  `idle_rss_kb: 52880`
  `idle_cpu_percent_average: 0.0`
- Relaunched the updated Release app for testing.
- Release app stayed running after the 30s file watcher startup delay that previously crashed.
- Release smoke benchmark passed on 2026-04-25:
  `launch_to_pid_ms: 96`
  `idle_rss_kb: 52288`
  `idle_cpu_percent_average: 0.0`
- Latest benchmark artifact:
  `benchmarks/2026-04-25.json`
- Local visual smoke check passed for collapsed and expanded launcher states after the dynamic sizing rollback.
- Local visual smoke check passed after app-index changes: Option-Space, `term`, Terminal as first result.
- One Release smoke run immediately after adding `/System/Applications/Utilities` missed idle budgets while the app catalog cache rebuilt; the rerun with the refreshed catalog passed.
- Release app was left running for visual testing after the Settings redesign.
- Debug build passed after adding Quicklinks / Custom Web Searches:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release build passed after adding Quicklinks / Custom Web Searches:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Release build passed after simplifying the Settings sidebar Launcher icon:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Release build passed after restructuring the Quicklinks Settings pane with explicit Keyword, Name, URL Template, and Presets labels:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Debug and Release builds passed after adding Quicklink result icons, built-in `gh`/`yt`/`maps` artwork, plist migration for existing defaults, and Settings custom icon upload:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Release build passed after centering result source badges and increasing launcher result icon size:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Debug and Release builds passed after adding Universal Actions:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Debug build passed after adding the local AI plan, AI benchmark script, and Settings status pane:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- AI benchmark artifact written:
  `benchmarks/ai-2026-04-25.json`
  `ollama_version: 0.15.4`
  `selected_model: llama3.2:3b`
  `warm_first_token_ms: 90`
  `warm_tokens_per_second: 49.91`
  `embeddinggemma: not installed`
  `mempalace: command not found`
- Release smoke benchmark passed after the local AI Settings work:
  `launch_to_pid_ms: 240`
  `idle_rss_kb: 51072`
  `idle_cpu_percent_average: 0.0`
- Release build passed after wiring the `ai` / `?` trigger to the local Ollama answer panel:
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after wiring the `ai` / `?` trigger on 2026-04-25:
  `launch_to_pid_ms: 315`
  `idle_rss_kb: 51264`
  `idle_cpu_percent_average: 0.0`
- Debug and Release builds passed after replacing the separate AI answer window with the inline launcher answer view:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after replacing the separate AI answer window with the inline launcher answer view on 2026-04-25:
  `launch_to_pid_ms: 123`
  `idle_rss_kb: 75072`
  `idle_cpu_percent_average: 0.0`
- Debug and Release builds passed after adding selected-result AI Universal Actions:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Selected-result AI actions now include `Ask AI`, `Summarize`, and `Explain` for apps, files, URLs/web/quicklinks, clipboard items, and snippets. Context is selected-result-only, file previews are capped at 16 KB, URL pages are not fetched, and secret-like paths are denied.
- Release smoke benchmark passed after selected-result AI Universal Actions on 2026-04-25:
  `launch_to_pid_ms: 144`
  `idle_rss_kb: 75216`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after selected-result AI Universal Actions:
  `pid: 83040`
- Investigated a beachball in Release app `pid: 83040`; `sample` showed an infinite key event loop between `LauncherPanel.keyDown(with:)` and `InputField.keyDown(with:)`, with CPU around 108%.
- Fixed the hang by splitting `InputField.handleKeyCommand(_:)` from text insertion and making `LauncherPanel.keyDown(with:)` route printable keys to the field editor instead of calling `InputField.keyDown(with:)` directly.
- Debug and Release builds passed after the key event recursion fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the key event recursion fix on 2026-04-25:
  `launch_to_pid_ms: 112`
  `idle_rss_kb: 75488`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the key event recursion fix:
  `pid: 83907`
- Found a second delayed crash path in the file watcher: saving FSEvent IDs changed `UserDefaults`, which restarted the watcher through a broad defaults observer. The observer now tracks only full-disk/warmup settings before restarting.
- Fixed the Swift isolation assertion in the delayed FSEvents path by keeping the stream callback and debounce on the main dispatch queue; the index update still runs through detached utility work.
- Debug build passed after the FSEvents watcher stability fixes:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the key event and FSEvents stability fixes on 2026-04-25:
  `launch_to_pid_ms: 121`
  `idle_rss_kb: 75488`
  `idle_cpu_percent_average: 0.0`
- Release app stayed alive after the 30s delayed file watcher startup window:
  `pid: 87244`
  `cpu: 0.0%`
  `rss_kb: 104368`
- Targeted unified log check found no `BUG IN CLIENT`, `swift_task_checkIsolated`, `FSEvents`, or `Assertion failed` entries for the current Release app after the delayed watcher check.
- Replaced the popup Universal Actions menu with Tab-driven inline action mode. Pressing Tab locks the selected result, clears the input into an action/custom-AI field, and shows actions in the launcher lower pane instead of opening `NSMenu`.
- Right Arrow no longer opens actions; it is left to text cursor behavior. Command-/ remains as a secondary shortcut into the same inline mode.
- Inline action mode supports typing to filter actions, plus a dynamic `Ask AI: <typed question>` action that uses only the locked result as context.
- Regenerated the Xcode project after adding `InlineActionsView.swift`:
  `xcodegen generate`
- Debug build passed after Tab inline action mode:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after Tab inline action mode on 2026-04-25:
  `launch_to_pid_ms: 100`
  `idle_rss_kb: 75056`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after Tab inline action mode:
  `pid: 89391`
- Fixed inline action row padding after screenshot review: rows now use full result-row height and center the title/subtitle stack, removing overlap between action title and subtitle.
- Debug build passed after the inline action padding fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the inline action padding fix on 2026-04-25:
  `launch_to_pid_ms: 98`
  `idle_rss_kb: 75296`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the inline action padding fix:
  `pid: 90282`
- Aligned inline action badges with the locked-result right rail: row badges now use the same 68pt width and a larger right inset so `Return` / `AI` no longer feel cramped against the edge.
- Debug build passed after the inline action badge padding fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the inline action badge padding fix on 2026-04-25:
  `launch_to_pid_ms: 102`
  `idle_rss_kb: 75136`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the inline action badge padding fix:
  `pid: 90719`
- Removed horizontal drift in inline action mode: the actions table now disables horizontal scrolling/elasticity, constrains its document width to the visible clip width, and resets horizontal offset on layout/reload.
- Made the `Locked` badge use the same centered badge control as row badges.
- Debug build passed after the inline action horizontal-scroll fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the inline action horizontal-scroll fix on 2026-04-25:
  `launch_to_pid_ms: 110`
  `idle_rss_kb: 75376`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the inline action horizontal-scroll fix:
  `pid: 91126`
- Balanced inline action horizontal padding after screenshot review: header, table frame, row icon, and row badge now use matching left/right insets.
- Debug build passed after the inline action balanced-padding fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the inline action balanced-padding fix on 2026-04-25:
  `launch_to_pid_ms: 102`
  `idle_rss_kb: 75472`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the inline action balanced-padding fix:
  `pid: 91563`
- Replaced the inline action `NSTableView` with lightweight custom AppKit rows so selected backgrounds, icons, labels, and badges share one fixed-width coordinate system with no horizontal table drift.
- Debug build passed after replacing the inline action table:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after replacing the inline action table on 2026-04-25:
  `launch_to_pid_ms: 95`
  `idle_rss_kb: 75536`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after replacing the inline action table:
  `pid: 92006`
- Restored inline action reload behavior to select the first visible action after filtering, matching the previous table behavior.
- Debug build passed after the reload-selection correction:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the reload-selection correction on 2026-04-25:
  `launch_to_pid_ms: 106`
  `idle_rss_kb: 75568`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the reload-selection correction:
  `pid: 92408`
- Researched the semantic file finder direction before implementation: keep macOS Spotlight as the fast metadata/content candidate source, use capped PDF/text previews for reranking instead of broad reads, use rank fusion across independent candidate lists, and keep embeddings out of the keystroke path until an explicit background vector index exists.
- Added `FilePreviewReader` for shared capped previews. It reads small UTF-8 text samples, extracts text from the first few PDF pages through PDFKit, rejects sensitive-looking paths, skips very large PDFs, and runs from detached preview reranking instead of row rendering.
- Reused `FilePreviewReader` in selected-result AI context so file AI actions now get the same capped PDF/text support without duplicate preview code.
- Added semantic file finder triggers: `ai find`, `ai search`, `ai locate`, `ai show me`, `? find`, and `? search`.
- Semantic file finder now parses natural type/date phrases such as `pdf`, `documents`, `images`, `last month`, `this week`, `yesterday`, and `past 30 days`, expands common tax terms, then returns normal file results.
- Semantic file finder ranking now merges three bounded sources: fallback file index metadata, existing VISH filename search, and existing Spotlight content search. It shortlists candidates first, then reads tiny previews only for the top candidates.
- Added `.pdf` file filtering and file modification timestamps to the fallback index records. Old plist records remain readable through `decodeIfPresent`.
- Optimized date-filtered semantic index search to stay candidate-bounded when query tokens exist, with capped lazy modification-date reads only for older indexes that do not yet contain timestamps.
- Clarified terminology after review: the first AI file finder pass was natural-language intent parsing plus Spotlight/index/preview reranking. This was superseded on 2026-04-26 by opportunistic Ollama vector reranking.
- Disabled horizontal scrolling at the clip-view level for result rows, inline actions, and inline AI answers. Text answers now wrap to the visible width instead of creating a horizontal scroll range.
- Regenerated the Xcode project after adding the semantic finder and shared file preview reader:
  `xcodegen generate`
- Debug build passed after semantic file finder:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after semantic file finder on 2026-04-25:
  `launch_to_pid_ms: 93`
  `idle_rss_kb: 75552`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after semantic file finder:
  `pid: 94616`
- Debug build passed after horizontal-scroll clamp and AI file finder terminology clarification:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after horizontal-scroll clamp on 2026-04-25:
  `launch_to_pid_ms: 94`
  `idle_rss_kb: 75408`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after horizontal-scroll clamp:
  `pid: 97078`
- Fixed the visual regression from the first horizontal-scroll clamp: the custom clip view is now transparent, result table width is synchronized to the visible clip width after layout/reload, and inline AI text view width is clamped to the visible width.
- Debug build passed after the horizontal-scroll visual regression fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the horizontal-scroll visual regression fix on 2026-04-25:
  `launch_to_pid_ms: 94`
  `idle_rss_kb: 75424`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the horizontal-scroll visual regression fix:
  `pid: 98087`
- Moved the result-cell shortcut rail inward with a fixed trailing gutter so the last cell element no longer renders into the panel edge.
- Debug build passed after result-cell trailing gutter fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after result-cell trailing gutter fix on 2026-04-25:
  `launch_to_pid_ms: 103`
  `idle_rss_kb: 75584`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after result-cell trailing gutter fix:
  `pid: 98584`
- Researched and implemented actual local vector reranking for explicit AI file finder queries using Ollama `/api/embed`, keeping embeddings out of default search and startup.
- Added `SemanticVectorIndexStore`, an actor-backed binary plist cache at `Application Support/vish/file-vectors.plist`. It stores normalized Float32 embeddings keyed by file path, model, dimension, and modification time.
- Semantic file finder now embeds the query plus up to 16 bounded candidate previews per query, searches cached vectors by dot product, and labels vector-contributed rows as `Semantic match` / `Semantic + preview match`.
- `LocalAIClient` now supports Ollama embedding batches with `truncate: true` and `keep_alive: 5m`; Auto embedding model selection prefers installed embedding-style models before falling back to the selected chat model.
- Settings > AI now has a separate `Embedding` picker so users can choose a dedicated embedding model independently of the chat model.
- Local embedding smoke passed against the installed `llama3.2:3b` model:
  `embeddings: 2`
  `dimensions: 3072`
- Debug build passed after vector semantic search:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after vector semantic search on 2026-04-26:
  `launch_to_pid_ms: 94`
  `idle_rss_kb: 74944`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after vector semantic search:
  `pid: 22269`
- Debug build also passed after preserving the `Semantic match` subtitle through candidate normalization:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- AI benchmark passed for warm chat against installed `llama3.2:3b`; embedding works but misses the target without a dedicated embedding model:
  `warm_first_token_ms: 91`
  `warm_tokens_per_second: 48.26`
  `embed_8_docs_ms: 753`
  `embed_8_docs_budget_met: false`
- Fixed the `ai find ...` routing failure: explicit AI file-finder prefixes no longer fall through to chat for short or partial search bodies.
- Added Settings-triggered full vector indexing. Settings > Files > Warm now runs filename indexing, then semantic vector indexing when Local AI is enabled.
- Vector indexing now reads vector candidates from the file catalog, indexes document/code/text/PDF-like files in 8-item Ollama embedding batches, stores normalized Float32 vectors in `file-vectors.plist`, skips unchanged path/model/mtime records, and saves incrementally.
- Vector indexing pauses while the launcher is visible/interactive and invalidates cached vectors for paths touched by FSEvents.
- Semantic search no longer scans the full filename catalog when a non-empty token has no filename-index candidates; cached vector search handles those cases.
- Debug build passed after strict AI file-finder routing and vector indexing:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after strict AI file-finder routing and vector indexing on 2026-04-26:
  `launch_to_pid_ms: 85`
  `idle_rss_kb: 75600`
  `idle_cpu_percent_average: 0.02`
  `post_run_ps_cpu_percent: 0.0`
- Release app was relaunched for testing after vector-indexing implementation:
  `pid: 26313`
- Optimized semantic/vector indexing after confirming only `llama3.2:3b` was installed locally. Full vector indexing no longer falls back to chat models; it requires a dedicated embedding model and reports `Fast embedding model needed` instead of silently doing heavyweight background work.
- Settings > AI now filters embedding choices to embedding-like models and can install/select `embeddinggemma` through Ollama `/api/pull` with non-streaming progress state.
- Semantic queries now embed only the query and search cached vectors. They no longer opportunistically embed up to 16 file previews during typing/selection, so query-time semantic search cannot trigger preview reads and vector writes.
- Background semantic indexing was made lighter: 16-item embedding batches, 2-minute embedding keep-alive, 4 KB/1200-character/1-page preview caps, less frequent vector cache saves, and a longer pause while the launcher is interactive.
- Debug build passed after semantic index optimization:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after semantic index optimization on 2026-04-26:
  `launch_to_pid_ms: 109`
  `idle_rss_kb: 75344`
  `idle_cpu_percent_average: 0.0`
- AI benchmark passed for warm chat, but embedding benchmark is intentionally blocked until `embeddinggemma` is installed:
  `installed_models: llama3.2:3b`
  `warm_first_token_ms: 79`
  `warm_tokens_per_second: 51.07`
  `embeddinggemma: not installed`
- Fixed Settings indexing progress appearing stuck at 96% after semantic indexing finished. Cause: the semantic progress poller swallowed cancellation from `Task.sleep` and could apply one stale final snapshot after the parent task set completion. The poller now exits after cancellation, and finished semantic snapshots map to 100%.
- Debug and Release builds passed after the semantic progress fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
  `xcodebuild -scheme vish -configuration Release -destination 'platform=macOS,arch=arm64'`
- Release app was relaunched for testing after the semantic progress fix:
  `pid: 29630`

## 2026-04-26 - Optimization Task Batch

- Added `docs/OPTIMIZATION_TASKS.md` as the tracked performance checklist and marked the first optimization batch complete.
- Fixed local AI model routing so chat requests ignore embedding-only models. Settings chat picker now filters out embedding-style models.
- Updated `./scripts/ai-benchmark.sh` to auto-select chat models only and report cold/warm chat plus cold/warm embedding timings.
- Settings now releases its SwiftUI content and window reference on close instead of retaining the full Settings tree for the app lifetime.
- Result rows now use a bounded icon cache and load uncached file/app icons at utility priority, keeping placeholders on the first render path.
- `scripts/signpost-report.sh` now includes the `Search` signpost alongside hotkey, keystroke, and Spotlight timings.
- Semantic vector search now scores directly from stored Float32 `Data`, trims ranked candidates before final file-existence checks, and avoids rebuilding arrays for every stored vector.
- Debug build passed after the optimization batch:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- AI benchmark passed with chat/embedding split:
  `selected_model: llama3.2:3b`
  `warm_first_token_ms: 88`
  `warm_tokens_per_second: 54.16`
  `warm_embedding_8_docs_ms: 120`
  `cold_embedding_8_docs_ms: 11743`
- Release smoke benchmark passed after the optimization batch on 2026-04-26:
  `launch_to_pid_ms: 123`
  `idle_rss_kb: 71072`
  `idle_cpu_percent_average: 0.0`
- Release app is running for testing after the optimization batch:
  `pid: 31141`

## 2026-04-26 - Semantic Trigger Fix

- Fixed `ai find` without a trailing query falling through to generic `Ask local AI`. Semantic commands now claim exact command text as soon as it is typed: `ai find`, `ai search`, `ai locate`, `ai show me`, `? find`, and `? search`.
- Empty semantic commands now show a compact prompt row: `Find files with AI` with an example query, instead of invoking chat.
- Debug build passed after the trigger fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the trigger fix on 2026-04-26:
  `launch_to_pid_ms: 91`
  `idle_rss_kb: 75328`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the trigger fix:
  `pid: 32370`

## 2026-04-26 - AI Model Picker Install Flow

- Reworked Settings > AI model selection from installed-model-only to a curated install/select picker.
- The chat model dropdown now shows recommended options even before they are installed:
  `qwen3.5:4b` as Recommended, `qwen3.5:9b` as Quality, and `llama3.2:3b` as Fast.
- The large `qwen3.5:35b-a3b-coding-nvfp4` MLX option is only exposed on Macs with at least 32 GB unified memory.
- Selecting a missing chat model shows an `Install` button. Install pulls through Ollama `/api/pull`, refreshes local model tags, and saves the selected chat model when the pull succeeds.
- Existing installed custom chat models are still shown below the curated choices.
- Chat model install state is separate from embedding model install state; embedding search still uses the dedicated `embeddinggemma` path.
- Debug build passed after the AI model picker install flow:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the AI model picker install flow on 2026-04-26:
  `launch_to_pid_ms: 102`
  `idle_rss_kb: 75424`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the AI model picker install flow:
  `pid: 32992`

## 2026-04-26 - AI Model Install Compatibility Fix

- Investigated the Settings install failure for `qwen3.5:4b`. Direct Ollama pull returned:
  `412: The model you are attempting to pull requires a newer version of Ollama.`
- Updated the curated chat model picker to version-gate newer Qwen tags. On Ollama versions before 0.19, Settings now offers `qwen3:4b` recommended, `qwen3:8b` quality, and `llama3.2:3b` fast. Qwen 3.5 and MLX options only appear on newer Ollama versions.
- Improved pull error handling so newer-Ollama failures display `Update Ollama to install <model>` instead of a generic install failure.
- Added runtime chat-model fallback: if preferences point to a missing model, `LocalAIClient` uses the best installed chat model instead of failing the AI request.
- Added Settings migration for unsupported stored `qwen3.5:*` selections on older Ollama; if `qwen3:4b` is installed it becomes the active chat model.
- Installed compatible `qwen3:4b` locally through Ollama for testing.
- Debug build passed after the compatibility fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- AI benchmark passed with `qwen3:4b`:
  `warm_first_token_ms: 103`
  `warm_tokens_per_second: 33.23`
  `warm_embedding_8_docs_ms: 116`
- Release smoke benchmark passed after the compatibility fix on 2026-04-26:
  `launch_to_pid_ms: 114`
  `idle_rss_kb: 74464`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the compatibility fix:
  `pid: 33623`

## 2026-04-26 - AI Model Disk Guard

- Investigated the Settings install failure for `qwen3:8b`. Direct Ollama pull failed with:
  `no space left on device`
- Confirmed installed local models were preserved:
  `qwen3:4b`, `embeddinggemma:latest`, and `llama3.2:3b`.
- Removed only the failed partial `qwen3:8b` Ollama blob left by the pull attempt; no installed model was removed.
- Current actual available disk after partial cleanup is about `4.1 GiB`, which is below the 8B guard threshold.
- Updated Settings > AI to use actual available disk capacity before installing missing curated models. Already-installed models stay visible.
- The install path also rechecks disk synchronously if Settings has not finished its Ollama refresh yet, so a fast click cannot bypass the guard.
- Set the local test default back to the installed model:
  `ai.model: qwen3:4b`
- Improved Ollama pull errors so no-space failures surface as `Free <N> GB to install <model>.`
- Debug build passed after the disk guard:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the disk guard on 2026-04-26:
  `launch_to_pid_ms: 104`
  `idle_rss_kb: 75600`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the disk guard:
  `pid: 35225`

## 2026-04-26 - AI Model Options Visibility

- Adjusted Settings > AI so compatible curated model options remain visible even on low disk.
- Missing models without enough actual free disk now show `Needs <N> GB free` in the dropdown.
- Selecting a low-disk model keeps the option visible but shows a disabled `Need Space` install state, preventing a failed Ollama pull without hiding the choice.
- Removed low-disk selection migration; runtime AI still falls back to an installed chat model until the selected model is installed.
- Debug build passed after keeping low-disk model options visible:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after keeping low-disk model options visible:
  `launch_to_pid_ms: 93`
  `idle_rss_kb: 75584`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after keeping low-disk model options visible:
  `pid: 39122`

## 2026-04-26 - Blank Launcher Placeholder

- Removed the default `Search` placeholder from the normal launcher input so the bar opens blank and focused.
- Kept the contextual `Ask AI or filter actions` placeholder only for Tab inline action mode.
- Debug build passed after removing the launcher placeholder:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after removing the launcher placeholder:
  `launch_to_pid_ms: 101`
  `idle_rss_kb: 75248`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after removing the launcher placeholder:
  `pid: 39711`

## 2026-04-26 - Rich Preview And Actions V1

- Added `docs/RICH_EXPERIENCE_TASKS.md` as the six-item implementation tracker for preview/detail/buffer/adaptive actions.
- Added a delayed selection preview pane. Results render first; preview work starts only after a 160 ms stable selection delay and cancels on query/selection changes.
- Added bounded preview metadata for files, apps, URLs, text-like results, snippets, AI rows, calculator copies, and system actions. File preview reads are capped and run off the main thread.
- Added `Command-Y` Quick Look for selected local results and `Command-I` detail mode for a larger inline preview.
- Added `Command-B` in-memory file buffer plus Tab actions for copy buffered paths, reveal buffered files, ask AI about buffered files, and clear buffer.
- Added lightweight local action-history ranking for Tab actions while keeping Return as the stable primary action.
- Regenerated the Xcode project with XcodeGen so the new preview source files are compiled.
- Debug build passed after the rich preview/action slice:
  `xcodegen generate`
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the rich preview/action slice:
  `launch_to_pid_ms: 135`
  `idle_rss_kb: 74992`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the rich preview/action slice:
  `pid: 44941`

## 2026-04-27 - Image Preview And Pane Spacing

- Fixed screenshot/image previews being treated as failed text previews. Image files now generate a bounded thumbnail off the main thread and show `Image preview` instead of `Preview unavailable: binary content`.
- Added an image surface inside the right preview pane with subtle border/background styling; text/body previews remain unchanged for non-image files.
- Increased the expanded launcher height and widened the right preview pane when it is visible, while leaving the collapsed launcher size unchanged.
- Debug build passed after the image preview/layout fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the image preview/layout fix:
  `launch_to_pid_ms: 153`
  `idle_rss_kb: 75504`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the image preview/layout fix:
  `pid: 60328`

## 2026-04-27 - Result Chip Layout Fix

- Fixed result-row source chips (`File`, `Quick`, `Web`, etc.) overlapping title/subtitle text when the right preview pane narrows the result column.
- Made row layout responsive: command-number hints hide in compact result columns, chip width/insets are tighter, and text width no longer forces overlap.
- Slightly reduced the preview split width so the result list keeps enough horizontal room while preserving the larger preview pane.
- Debug build passed after the chip layout fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the chip layout fix:
  `launch_to_pid_ms: 92`
  `idle_rss_kb: 75872`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the chip layout fix:
  `pid: 61063`

## 2026-04-27 - Result Chip Gutter Fix

- Pulled result-row source chips inward with a larger trailing gutter so chips stay inside the selected row background in compact preview split mode.
- Made source chip width content-aware, keeping short labels compact while still fitting longer labels such as `Snippet`.
- Debug build passed after the chip gutter fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the chip gutter fix:
  `launch_to_pid_ms: 93`
  `idle_rss_kb: 75808`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the chip gutter fix:
  `pid: 61560`

## 2026-04-27 - AI Reasoning Leak Fix

- Fixed Qwen/Ollama reasoning text leaking into the inline AI answer view for prompts like `who are you`.
- Strengthened the local AI system prompt to require final-answer-only output and to forbid hidden reasoning, scratchpads, prompt text, analysis, and `<think>` tags.
- Added `/no_think` to Qwen-family user prompts because older Ollama/Qwen paths may ignore the `think: false` API field.
- Added `AIStreamSanitizer` in `LocalAIClient` so streamed chunks are filtered before UI append. It suppresses `<think>...</think>` blocks, handles split tags, and conservatively buffers the start of each response to avoid showing reasoning preambles.
- Debug build passed after the AI reasoning leak fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the AI reasoning leak fix:
  `launch_to_pid_ms: 105`
  `idle_rss_kb: 75584`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the AI reasoning leak fix:
  `pid: 62140`

## 2026-04-27 - Production Settings And Onboarding Pass

- Added `docs/PRODUCTION_READINESS.md` with UX gates, performance gates, release flow, and current blockers for production readiness.
- Reworked Settings to open on a compact Setup pane with readiness cards for Launcher, Files, Clipboard, and AI, plus the core production performance budgets.
- Kept readiness checks Settings-only: Accessibility status is read locally, Ollama is only checked when Local AI is enabled, and no launcher hot-path code was touched.
- Tightened Settings indexing progress refresh to 4 Hz max so SwiftUI progress updates do not churn while indexing.
- Polished onboarding into a four-step flow: value, permissions, feature defaults, and ready/shortcuts. Optional features remain skippable.
- Debug build passed after the production Settings/onboarding pass:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after the production Settings/onboarding pass:
  `launch_to_pid_ms: 100`
  `idle_rss_kb: 75536`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the production Settings/onboarding pass:
  `pid: 62846`

## 2026-04-27 - Settings Titlebar Clearance Fix

- Moved the Settings content down below the macOS traffic-light window controls so the VISH logo no longer overlaps the close/minimize/zoom buttons.
- Increased the Settings window height from 500 to 524 points to preserve bottom spacing after adding top clearance.
- Increased the Settings top clearance again to 42 points and window height to 536 points after screenshot review showed the logo still too close to the traffic lights.
- Debug build passed after the titlebar clearance fix:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Release smoke benchmark passed after relaunching the corrected Settings build:
  `launch_to_pid_ms: 107`
  `idle_rss_kb: 75296`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the titlebar clearance fix:
  `pid: 65724`

## 2026-04-27 - GitHub Alpha Release Prep

- Added a public-facing `README.md` covering VISH features, install flow, command cheatsheet, optional permissions, performance targets, build commands, and alpha status.
- Added `docs/releases/v0.1.0-alpha.1.md` for GitHub release notes.
- Built the first public alpha DMG:
  `dist/vish-0.1.0-alpha.1.dmg`
- DMG checksum:
  `663ec5a36a4c6707fe2d45324801d039a1bf89207f3b9ee72ca59cb08dcc6650`
- Release archive command passed through:
  `scripts/release.sh 0.1.0-alpha.1`
- Created public GitHub repository:
  `https://github.com/itisrmk/VISH`
- Pushed `main` and tag:
  `v0.1.0-alpha.1`
- Published GitHub prerelease with downloadable DMG:
  `https://github.com/itisrmk/VISH/releases/tag/v0.1.0-alpha.1`
- Direct DMG URL:
  `https://github.com/itisrmk/VISH/releases/download/v0.1.0-alpha.1/vish-0.1.0-alpha.1.dmg`

## 2026-04-27 - Simple Mac App Logo

- Added a minimal macOS app icon asset catalog at `vish/Resources/Assets.xcassets/AppIcon.appiconset`.
- Logo direction: blue rounded-square mark with subtle macOS-style depth and a white `V`.
- Generated required macOS icon PNG sizes from 16 through 1024 px.
- Updated `project.yml` so regenerated Xcode projects keep `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- Regenerated `vish.xcodeproj` with `xcodegen generate`.
- Debug build passed and verified the built app contains:
  `Contents/Resources/AppIcon.icns`
  `Contents/Resources/Assets.car`
- Built and published `v0.1.0-alpha.2` so the downloadable DMG includes the new logo:
  `https://github.com/itisrmk/VISH/releases/tag/v0.1.0-alpha.2`
- Alpha 2 DMG checksum:
  `aceff9e33133f5f7c291613ae2639155c3cb83912293b1717b307589cac4bb8d`

## 2026-04-28 - Menu Bar Logo Polish

- Replaced the macOS menu bar text item `v` with a fixed-width image-only status item.
- Added a small monochrome template logo drawn in AppKit so macOS tints it correctly in light/dark menu bars.
- Debug build passed after the menu bar logo change:
  `xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'`
- Built the alpha 3 DMG so the downloadable app includes the menu bar logo polish:
  `dist/vish-0.1.0-alpha.3.dmg`
- Alpha 3 DMG checksum:
  `598bb57be966b9620588845b1db89874c0bcf0160a3411507ed219ae5b127d59`
- Release smoke benchmark passed after the menu bar logo polish:
  `launch_to_pid_ms: 97`
  `idle_rss_kb: 75520`
  `idle_cpu_percent_average: 0.0`
- Release app was relaunched for testing after the menu bar logo polish:
  `pid: 91276`

### Known Gaps

- Production Settings/onboarding still needs user screenshot review; build verification is not a visual approval.
- Local AI is still early: the basic `ai` / `?` trigger, inline streaming answer view, selected-result `Ask AI` / `Summarize` / `Explain` actions, and semantic file finder exist. Explicit AI file finder now has Settings-triggered Ollama vector indexing/reranking, but MemPalace integration, citations UI, Find Related, Save Answer as Snippet, automatic idle vector ingestion, and tool calling are not implemented yet.
- This machine has Ollama 0.15.4, not the Ollama 0.19+ MLX preview path. Upgrade Ollama before MLX-specific benchmarking.
- Pull an embedding model such as `embeddinggemma` before measuring embedding budgets.
- Install MemPalace from an official source before measuring memory search.
- Frame-level signpost analysis in Instruments is still needed for hotkey-to-frame, keystroke-to-render, and Spotlight p95.
- Sparkle appcast hosting/signing keys are not configured yet.
- Full Developer ID signed and notarized release flow still requires real signing identity and `AC_PROFILE`; local archive/DMG creation has been verified.
- The worktree contains large legacy Rust deletions and untracked native Swift project files. Do not revert or restore those unless explicitly requested.
