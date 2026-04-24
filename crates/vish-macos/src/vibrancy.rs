//! NSVisualEffectView vibrancy application.
//!
//! Thin wrapper around `window_vibrancy::apply_vibrancy` that fixes the
//! material/state/radius choice vish uses and types the error as a local
//! `thiserror` variant.

use raw_window_handle::HasWindowHandle;
use window_vibrancy::{NSVisualEffectMaterial, NSVisualEffectState, apply_vibrancy};

/// Errors raised by this module.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// `window_vibrancy::apply_vibrancy` failed.
    #[error("window-vibrancy: {0}")]
    Vibrancy(#[from] window_vibrancy::Error),
}

/// Apply the vish panel vibrancy — `HudWindow` material,
/// `FollowsWindowActiveState`, no corner radius clip (GPUI draws the rounded
/// rect). Material/state choices documented in `NOTES.md`.
///
/// **Thread:** must be called from the main thread. `apply_vibrancy` touches
/// the window's content view tree; AppKit view-hierarchy mutation is
/// main-thread-only per CLAUDE.md §10 #1.
///
/// **Precondition:** `window` must already exist and have its content view
/// installed — call after GPUI has opened the window.
pub fn apply<W>(window: &W) -> Result<(), Error>
where
    W: HasWindowHandle,
{
    apply_vibrancy(
        window,
        NSVisualEffectMaterial::HudWindow,
        Some(NSVisualEffectState::FollowsWindowActiveState),
        None,
    )?;
    Ok(())
}
