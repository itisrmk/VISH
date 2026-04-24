//! NSPanel augmentation for GPUI `WindowKind::PopUp` windows.
//!
//! GPUI already subclasses `NSPanel` when a window is opened with
//! `WindowKind::PopUp` (`gpui_macos/src/window.rs:129, 672-679`). It sets:
//!
//! - `NSWindowStyleMaskNonactivatingPanel` (line 80, 673)
//! - `canBecomeKeyWindow → YES`, `canBecomeMainWindow → YES` (lines 322-329)
//! - `NSPopUpWindowLevel = 101` (line 874)
//! - `collectionBehavior = CanJoinAllSpaces | FullScreenAuxiliary` (lines 879-882)
//! - A tracking area for `mouseMoved` even when inactive (lines 863-872)
//!
//! That is most of what the Week 2 exit test needs. What we add here:
//!
//! 1. **`MoveToActiveSpace`** in the collection behavior — PHASE_1_PLAN §3
//!    requires it; GPUI does not set it. Without it, the panel stays on the
//!    space where it was first shown rather than following Spaces. Note that
//!    `CanJoinAllSpaces` (GPUI's default) and `MoveToActiveSpace` are mutually
//!    exclusive at the AppKit level — setting both raises an Obj-C exception.
//!    We swap the bit rather than OR, preserving `FullScreenAuxiliary` and
//!    any other bits GPUI sets.
//! 2. A single entry point to apply options, preserving GPUI's `FullScreenAuxiliary`
//!    (and any future additions) via read-mask-write rather than wholesale replace.
//!
//! We deliberately do **not** expose a `Panel::show/hide` API — that is
//! GPUI's job via `cx.hide()` / `cx.activate_window()` (Loungy pattern,
//! `loungy/src/window.rs:96-114`). Duplicating it would fight GPUI's
//! internal state.

use objc2_app_kit::{NSPanel, NSView, NSWindowCollectionBehavior};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};

/// Errors raised by this module.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// The window did not produce an `AppKitWindowHandle` (e.g. it is a test
    /// window or a platform we don't support).
    #[error("window did not expose an AppKit handle")]
    NotAppKit,

    /// The backing `NSView` has not been installed into an `NSWindow` yet.
    #[error("NSView is not attached to an NSWindow")]
    NoWindow,

    /// The backing `NSWindow` is not an `NSPanel` — caller likely used
    /// `WindowKind::Normal` instead of `WindowKind::PopUp`.
    #[error("window is not an NSPanel (was WindowKind::PopUp used?)")]
    NotPanel,

    /// `HasWindowHandle::window_handle()` returned an error.
    #[error("window handle: {0}")]
    Handle(#[from] raw_window_handle::HandleError),
}

/// Tunables applied to the panel in a single call.
///
/// Defaults: follow the active Space (PHASE_1_PLAN §3).
#[derive(Debug, Clone, Copy)]
pub struct Options {
    /// Replace `NSWindowCollectionBehavior::CanJoinAllSpaces` (GPUI's default
    /// for `WindowKind::PopUp`) with `MoveToActiveSpace`, preserving every
    /// other bit GPUI set (`FullScreenAuxiliary`, etc).
    ///
    /// These two flags are mutually exclusive at the AppKit level — setting
    /// both raises an Obj-C exception from `-[NSWindow setCollectionBehavior:]`
    /// which crosses our Rust frames as a non-unwind abort. See `NOTES.md`
    /// §"collectionBehavior" for why this is a swap, not an OR.
    ///
    /// If false, we leave `collectionBehavior` alone (panel appears on every
    /// Space simultaneously, GPUI's default).
    pub move_to_active_space: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            move_to_active_space: true,
        }
    }
}

/// Apply vish-specific panel tweaks to a GPUI `WindowKind::PopUp` window.
///
/// **Thread:** must be called from the main thread. Every AppKit setter
/// touched here (`setCollectionBehavior:`) is main-thread-only per CLAUDE.md
/// §10 #1. Use `dispatch2::DispatchQueue::main()` to hop if you are not
/// already on main.
///
/// **Precondition:** `window` must be a GPUI window opened with
/// `WindowKind::PopUp`. Calling on `WindowKind::Normal` is well-defined but
/// pointless — the window is not an `NSPanel`.
///
/// Reference for the `object_setClass` swizzling trick (if we ever need to
/// override `canBecomeMainWindow → NO`): `tauri-nspanel/src/panel.rs:558-628`.
pub fn configure<W>(window: &W, opts: Options) -> Result<(), Error>
where
    W: HasWindowHandle,
{
    let raw = window.window_handle()?.as_raw();
    let RawWindowHandle::AppKit(appkit) = raw else {
        return Err(Error::NotAppKit);
    };

    // SAFETY: `raw-window-handle` 0.6 guarantees `appkit.ns_view` is a valid,
    // retained `NSView*` for the lifetime of the borrowed `WindowHandle`
    // (docs at `raw_window_handle::WindowHandle`). GPUI retains the view
    // for the window's lifetime (`gpui_macos/src/window.rs:1700-1709`), and
    // we dereference synchronously — the handle outlives this block.
    let view: &NSView = unsafe { &*appkit.ns_view.as_ptr().cast::<NSView>() };

    let ns_window = view.window().ok_or(Error::NoWindow)?;
    let panel = ns_window.downcast_ref::<NSPanel>().ok_or(Error::NotPanel)?;

    if opts.move_to_active_space {
        let current = panel.collectionBehavior();
        let new = (current & !NSWindowCollectionBehavior::CanJoinAllSpaces)
            | NSWindowCollectionBehavior::MoveToActiveSpace;
        panel.setCollectionBehavior(new);
        tracing::debug!(
            was = current.bits(),
            now = new.bits(),
            "panel: replaced CanJoinAllSpaces with MoveToActiveSpace"
        );
    }

    Ok(())
}
