# vish-macos — NSPanel + hotkey architecture sketch (Phase 1 Week 2 Task A)

> Reviewable design for the macOS integration crate. No runtime code yet. All
> public signatures exist as `todo!()` stubs; the workspace compiles. Task B
> fills in the bodies after human greenlight on the open questions below.

## TL;DR — the load-bearing finding

**GPUI already creates an `NSPanel` subclass for `WindowKind::PopUp`.** Our
crate is an *augmentation layer*, not a panel-from-scratch builder. Everything
we add is the delta between "GPUI panel defaults" and "vish panel requirements"
(PHASE_1_PLAN.md §3).

Source:
`third-party/reference/zed-reference/crates/gpui_macos/src/window.rs`
- line 129 — `PANEL_CLASS = build_window_class("GPUIPanel", class!(NSPanel));`
- line 80  — `NSWindowStyleMaskNonactivatingPanel = 1 << 7`
- lines 322-329 — overrides `canBecomeMainWindow → YES`, `canBecomeKeyWindow → YES`
- lines 672-679 — `WindowKind::PopUp` adds `NonactivatingPanel` mask + allocates `PANEL_CLASS`
- lines 859-883 — `PopUp` branch sets `NSPopUpWindowLevel` (101), `NSWindowAnimationBehaviorUtilityWindow`, `collectionBehavior = CanJoinAllSpaces | FullScreenAuxiliary`, and a tracking area for mouseMoved even when inactive

## Intended public API

Deliberately minimal. Three modules, one function each (plus one type):

```rust
// vish_macos::hotkey
pub type Event = global_hotkey::GlobalHotKeyEvent;
pub struct Hotkey { /* owns GlobalHotKeyManager */ }
impl Hotkey {
    pub fn register(hotkey: global_hotkey::hotkey::HotKey) -> Result<Self, Error>;
    pub fn on_fire() -> &'static global_hotkey::GlobalHotKeyEventReceiver;
}

// vish_macos::panel
pub struct Options { pub move_to_active_space: bool }
pub fn configure<W: HasWindowHandle>(window: &W, opts: Options) -> Result<(), Error>;

// vish_macos::vibrancy
pub fn apply<W: HasWindowHandle>(window: &W) -> Result<(), Error>;
```

Each module has a local `Error` enum (thiserror). No `anyhow` in a library
crate (CLAUDE.md §5).

### What is **not** here and why

- **`Panel::new` / `Panel::show` / `Panel::hide`**. GPUI owns NSPanel creation
  (`cx.open_window(WindowKind::PopUp, ...)`) and show/hide
  (`cx.hide()` / `cx.activate_window()`, Loungy pattern
  `loungy-reference/src/window.rs:96-114`). Re-exposing these would duplicate
  GPUI's internal state machine and fight its `observe_window_activation`
  callback. See §"Open questions" — this diverges from the task-spec's
  suggested surface deliberately.
- **Activation policy.** `NSApplication::setActivationPolicy(Accessory)` is a
  one-line `objc2-app-kit` call that belongs in `apps/vish/src/main.rs`
  directly (same pattern as `third-party/spikes/s3-hotkey/src/main.rs:27-29`).
  Wrapping it here would be speculative abstraction.
- **Tray / menus.** `tray-icon` and `muda` are not in Week 2's exit test
  (PHASE_1_PLAN.md §3). Added when we reach the tray story in a later week.

## Loungy patterns being ported

Reading `third-party/reference/loungy-reference/`. Loungy uses cocoa 0.25 and
global-hotkey 0.4.2 — we are on objc2 0.6 and global-hotkey 0.7, so we adapt
shape-for-shape, never copy-paste.

- **`loungy/src/main.rs:35-45`** — `async_std::main`, single `App::new().run(...)`
  entry. **Adapted:** we use GPUI's `gpui::Application::new().run(...)` with
  tokio on non-main threads (per CLAUDE.md §2 async runtime section). Loungy's
  `async_std` choice pre-dates GPUI's tokio story.
- **`loungy/src/app.rs:25-50`** — `run_app` opens a window via
  `cx.open_window(WindowStyle::Main.options(bounds), ...)` and calls
  `HotkeyManager::init(cx)` / `Window::init(cx)` inside the opened window
  callback. **Adapted verbatim** — `apps/vish/src/main.rs` will mirror this
  shape in Task B.
- **`loungy/src/window.rs:21-62` (WindowStyle::Main)** — sets
  `WindowKind::PopUp`, `titlebar = None`, `is_movable = false`, bounds centered.
  **Adapted verbatim.** This produces the GPUI-created NSPanel we augment.
- **`loungy/src/window.rs:64-132` (Window global)** — `open/toggle/close/hide`
  via `cx.hide()` + `cx.activate_window()`. Stores a `hidden: bool` flag and
  wraps GPUI's window calls. **Adapted verbatim**, but lives in `vish-ui`, not
  `vish-macos` (no AppKit calls here — it's pure GPUI).
- **`loungy/src/hotkey.rs:45-102` (HotkeyManager::init)** — registers a
  fallback hotkey, spawns a GPUI task that polls `try_recv` every 50 ms and
  calls `Window::toggle(cx)` on fire. **Rejected in part** — the 50 ms poll is
  8 frames at 120Hz, unacceptable (CLAUDE.md §3 threading invariants, 8 ms
  ceiling). We replace with a dedicated `std::thread` blocking on `recv()`,
  forwarding via `tokio::sync::mpsc::UnboundedSender`, GPUI side awaits
  (details in §"Hotkey↔GPUI bridge").
- **No NSPanel subclassing, no explicit `collectionBehavior`, no activation
  policy.** Loungy never touches these — it relies entirely on GPUI's
  `WindowKind::PopUp` defaults. vish *adds* `MoveToActiveSpace` because the
  PHASE_1_PLAN exit test requires following Spaces.

## tauri-nspanel patterns being ported

Reading `third-party/reference/tauri-nspanel-reference/`.

- **`tauri-nspanel/src/panel.rs:112-202`** — the `panel!` macro's
  `objc2::define_class!` block: supers `NSPanel`, overrides
  `canBecomeKeyWindow` / `canBecomeMainWindow` via a `config` DSL.
  **Studied, not ported as a class.** GPUI already has these overrides (YES/YES);
  if we ever need to flip `canBecomeMainWindow → NO` (see Open Question #2)
  we port the `object_setClass` swizzle from
  `tauri-nspanel/src/panel.rs:558-628` — swap GPUI's `GPUIPanel` class pointer
  for our own subclass on the fly. This is the "~40 lines of objc2" CLAUDE.md
  §2 cites. Until we prove we need it, we don't.
- **`tauri-nspanel/src/panel.rs:499-503` (`set_collection_behavior`)** —
  `msg_send![panel, setCollectionBehavior: behavior]`. **Adapted:** our
  `panel::configure` reads current behavior with `collectionBehavior()`, ORs
  in `MoveToActiveSpace`, writes back — doesn't clobber whatever GPUI set.
- **`tauri-nspanel/examples/collection_behavior.rs`** — confirms the correct
  enum variant names (`CanJoinAllSpaces`, `FullScreenAuxiliary`, etc.) in
  objc2-app-kit 0.3. Spellings verified against docs.rs: variants are
  `NSWindowCollectionBehavior::MoveToActiveSpace`, not
  `NSWindowCollectionBehaviorMoveToActiveSpace`.

## GPUI integration model

**GPUI owns the NSPanel. We reach it through `raw-window-handle`.**

Evidence:
- `gpui_macos/src/window.rs:1700-1709` — `impl rwh::HasWindowHandle for MacWindow`
  returns an `AppKitWindowHandle` wrapping `self.native_view.cast()` (a
  `*mut c_void` pointing to `NSView`).
- `gpui/src/window.rs:5620-5624` — `impl HasWindowHandle for gpui::Window`
  forwards to the platform window.

So, given a `&gpui::Window` we can:

```rust
let handle = window.window_handle()?;                  // rwh::WindowHandle<'_>
let RawWindowHandle::AppKit(appkit) = handle.as_raw()  // rwh::AppKitWindowHandle
    else { return Err(Error::NotAppKit) };
// appkit.ns_view is NonNull<c_void> → NSView*
// NSView has `.window()` → NSWindow*
// For WindowKind::PopUp, that NSWindow* is actually an NSPanel (the GPUIPanel subclass).
// Cast to &NSPanel, then call setCollectionBehavior:.
```

This keeps us out of GPUI's internals — we only touch AppKit objects through a
public, versioned trait (`raw-window-handle = "0.6"`, matched by Zed's GPUI at
`gpui_macos/Cargo.toml:54` and `gpui/Cargo.toml:74`).

The `configure` and `apply` functions both take `impl HasWindowHandle` so
`gpui::Window` passes in directly.

## Thread model

Every public API is main-thread-only except `Hotkey::on_fire`. This matches
CLAUDE.md §10 invariant #1 (AppKit on main only) and §3 threading invariants.

| Function | Thread |
|---|---|
| `Hotkey::register` | **main** (Carbon handler installation on main run loop) |
| `Hotkey::on_fire` | any (returns `&'static Receiver<Event>`, which is `Send+Sync`) |
| `panel::configure` | **main** (calls `setCollectionBehavior:` on NSPanel) |
| `vibrancy::apply` | **main** (mutates NSView hierarchy inside the window) |

The hotkey `recv()` loop runs on a dedicated `std::thread::spawn` (CLAUDE.md
§5 async: blocking syscalls off cooperative executors). See §"Hotkey↔GPUI bridge".

## Activation policy

`NSApplicationActivationPolicy::Accessory`, confirmed working by S3 spike
(`third-party/spikes/s3-hotkey/src/main.rs:27-29`): global-hotkey fires with
no AX prompt, no Dock icon, no menu bar.

Not `Regular`: would add a Dock icon + menu bar, which we don't want for a
headless-at-rest launcher.

Not `Prohibited`: would prevent any window from becoming key, breaking text
input into the search field.

**Location:** `apps/vish/src/main.rs` directly calls
`NSApplication::sharedApplication(mtm).setActivationPolicy(Accessory)` before
entering GPUI's run loop, same as S3. No `vish_macos::activation` module —
that would be speculative abstraction over a one-liner.

## collectionBehavior

Target value: `MoveToActiveSpace | FullScreenAuxiliary`.

**Empirical finding from Task B runtime test:** `CanJoinAllSpaces` and
`MoveToActiveSpace` are mutually exclusive at the AppKit level. Setting both
raises an Obj-C exception from `-[NSWindow setCollectionBehavior:]` which
propagates as an unwind failure across our Rust frames (observed as a
misleading "Leases must be ended" GPUI panic because the Obj-C exception
skipped the normal return path). Apple's docs on this group are
under-specified in objc2-app-kit 0.3's re-exported headers but confirmed in
Apple's online reference: these two bits partition "appears on every space"
vs "follows the active space" behavior and you pick one.

GPUI sets `CanJoinAllSpaces | FullScreenAuxiliary` (`gpui_macos/src/window.rs:879-882`).
We **clear** `CanJoinAllSpaces` and **OR in** `MoveToActiveSpace`, preserving
`FullScreenAuxiliary`:

```rust
let new = (current & !NSWindowCollectionBehavior::CanJoinAllSpaces)
    | NSWindowCollectionBehavior::MoveToActiveSpace;
```

Why `MoveToActiveSpace` (PHASE_1_PLAN §3): the Raycast UX requires the panel
to pop on *whatever Space is currently active* when ⌥Space is pressed — not
to appear simultaneously on every Space. The visual/semantic difference
shows only when the user has multiple Spaces; on single-Space setups the
choice is invisible.

Note that GPUI does **not** set `IgnoresCycle` or `Stationary` — and we don't
want them either. `Stationary` defeats `MoveToActiveSpace`.

## Hotkey↔GPUI bridge

**Decision (commit in Task B, not Task A, but the shape is):**

1. Dedicated `std::thread::spawn` owns `global_hotkey::GlobalHotKeyEvent::receiver()`.
2. Thread loop: `let ev = rx.recv()?; tokio_tx.send(ev)?;` — blocking crossbeam
   `recv`, forwarded through `tokio::sync::mpsc::UnboundedSender<Event>`.
3. GPUI side: `cx.spawn(async move |cx| { while let Some(ev) = rx.recv().await
   { cx.update(|cx| dispatch_toggle(cx)).ok(); } })`. This uses GPUI's
   foreground executor; `cx.update` hops to the main thread for us.

Why not:
- **50 ms poll (Loungy).** 8 frames at 120Hz. Unacceptable jitter.
- **`crossbeam-channel` alone.** No async `.await` — we'd need to poll, back
  to problem 1.
- **`tokio::sync::mpsc` from the start.** `global-hotkey` hands us a crossbeam
  receiver; we can't replace it, only adapt.
- **`dispatch2::DispatchQueue::main().async_exec(...)` from the std::thread.**
  Works, but bypasses GPUI's own scheduling and won't compose with `cx.spawn`
  cancellation. The mpsc bridge is cleaner.

Channel: `tokio::sync::mpsc::unbounded_channel` — hotkey events are rare
(user keystrokes), no backpressure concern. No JoinHandle leak — the thread
owns the sender; when vish exits, dropping the sender closes the async side.

Reference to copy verbatim for the std::thread structure:
`third-party/spikes/s3-hotkey/src/main.rs:20-25`.

## Open questions / uncertainty flags

**These are the things I want human review on before Task B runs.**

1. **Panel API shape (A vs B).** I chose (A) `panel::configure(&window, opts)`
   — a single stateless function that augments GPUI's panel. Rejected (B) a
   `Panel::from_window → Panel` wrapper that owns `Retained<NSPanel>` and
   provides `show/hide`. Rationale: GPUI owns show/hide via `cx.hide()` /
   `cx.activate_window()` (Loungy pattern), and (B) would duplicate state.
   **Diverges from the task-spec's suggested minimum surface**
   (`Panel::new / show / hide`). Flagging for greenlight.

2. **`canBecomeMainWindow` divergence.** GPUI overrides it to `YES`
   (`gpui_macos/src/window.rs:323-325`). Tauri-nspanel convention is `NO`
   (so the panel doesn't register as the app's "main window"). For the Week 2
   exit test — "frontmost app keeps focus" — the `Nonactivating` mask +
   `Accessory` activation policy already achieve it; in practice an
   `Accessory` app has no main window anyway. **Proposal: do not fix in
   Week 2. Flag as a known GPUI divergence from the tauri convention.** If
   we later see focus-steal regressions, port the `object_setClass` swizzle
   from `tauri-nspanel/src/panel.rs:558-628`.

3. **`MoveToActiveSpace` application strategy.** Read-modify-write,
   specifically: clear `CanJoinAllSpaces` and OR `MoveToActiveSpace`.
   **Resolved in Task B at runtime.** Naïve OR-only raised an Obj-C exception
   at `setCollectionBehavior:` because the two bits are mutually exclusive
   (see §"collectionBehavior"). We preserve `FullScreenAuxiliary` and any
   other GPUI-set bits, swap the space-behavior bit.

4. **Hotkey→GPUI bridge exact mechanism.** Commit in Task B. Proposed pattern
   documented above. The alternative — calling `cx.update` directly from the
   std::thread via a cloned `AsyncAppContext` — is possible but not covered
   in GPUI's public docs I could verify; mpsc is uncontroversial.

5. **GPUI SHA drift.** The `zed-reference/` clone is at main HEAD as of
   2026-04-23. vish pins GPUI via `Cargo.lock` (per CLAUDE.md §2's pinning
   strategy). The findings in §TL;DR reflect current HEAD; **if
   `cargo update -p gpui` bumps the lock, re-verify the line numbers here**.
   The architectural shape (GPUI owns NSPanel, exposes HasWindowHandle) is
   older than 2026 and unlikely to change, but the exact line numbers will
   drift.

6. **`raw-window-handle` version matching.** Added as a direct dep at 0.6
   with `features = ["std"]` (required so `HandleError: std::error::Error` and
   thiserror's `#[from]` works). Matches Zed's `gpui_macos/Cargo.toml:54` and
   `window-vibrancy 0.6`'s `raw-window-handle = "0.6"`. If any of these bumps
   to 0.7, all three must bump together (rwh is not semver-compatible across
   major bumps) — the `AppKitWindowHandle` type moves crates.

7. **`canBecomeKeyWindow` for text input.** GPUI's override is `YES`. Our
   search panel needs text input (focus TextField), which requires
   `canBecomeKeyWindow == true`. Confirmed compatible. No action.

## Verification

All four commands green on this commit:
- `cargo build --workspace`
- `cargo test --workspace`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo fmt --all --check`

`todo!()` has type `!` and coerces to any return type, so every signature
compiles despite empty bodies. No runtime code executes — `cargo test` on an
empty crate passes trivially.
