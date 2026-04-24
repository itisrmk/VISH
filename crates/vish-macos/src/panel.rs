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
//!    space where it was first shown rather than following Spaces.
//! 2. A single entry point to apply options, preserving any future GPUI
//!    additions by reading the current `collectionBehavior` and OR-ing our bit
//!    rather than overwriting wholesale.
//!
//! We deliberately do **not** expose a `Panel::show/hide` API — that is
//! GPUI's job via `cx.hide()` / `cx.activate_window()` (Loungy pattern,
//! `loungy/src/window.rs:96-114`). Duplicating it would fight GPUI's
//! internal state.

use raw_window_handle::HasWindowHandle;

/// Errors raised by this module.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// The window did not produce an `AppKitWindowHandle` (e.g. it is a test
    /// window or a platform we don't support).
    #[error("window did not expose an AppKit handle")]
    NotAppKit,

    /// `HasWindowHandle::window_handle()` returned an error.
    #[error("window handle: {0}")]
    Handle(#[from] raw_window_handle::HandleError),
}

/// Tunables applied to the panel in a single call.
///
/// Defaults: follow the active Space (PHASE_1_PLAN §3).
#[derive(Debug, Clone, Copy)]
pub struct Options {
    /// Add `NSWindowCollectionBehavior::MoveToActiveSpace` on top of whatever
    /// GPUI already set. If false, we leave `collectionBehavior` alone.
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
pub fn configure<W>(_window: &W, _opts: Options) -> Result<(), Error>
where
    W: HasWindowHandle,
{
    todo!()
}
