//! Global hotkey registration and event forwarding.
//!
//! Thin wrapper over `global-hotkey` (Carbon `RegisterEventHotKey` under the
//! hood — does not require Accessibility per CLAUDE.md §10 #10 and the Phase 0
//! S3 spike). The manager must live for the duration of registration:
//! dropping it unregisters the hotkey system-wide.
//!
//! Events arrive on a crossbeam receiver owned by the `global-hotkey` crate.
//! The caller is responsible for bridging those events into GPUI's foreground
//! executor — see `NOTES.md` §"Hotkey↔GPUI bridge".

use global_hotkey::{
    GlobalHotKeyEvent, GlobalHotKeyEventReceiver, GlobalHotKeyManager, hotkey::HotKey,
};

/// Re-export so callers can type-annotate channel adapters without taking a
/// direct `global-hotkey` dependency.
pub type Event = GlobalHotKeyEvent;

/// Errors raised by this module.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// Underlying `global-hotkey` failure (OS registration, duplicate id, …).
    #[error("global-hotkey: {0}")]
    GlobalHotKey(#[from] global_hotkey::Error),
}

/// Owns the OS-level hotkey registration.
///
/// Construct once per process. Dropping the handle unregisters every hotkey it
/// owns — keep it alive for the lifetime of the UI.
pub struct Hotkey {
    _manager: GlobalHotKeyManager,
    _id: u32,
}

impl Hotkey {
    /// Register a single hotkey.
    ///
    /// **Thread:** must be called from the main thread.
    /// `GlobalHotKeyManager::new()` installs a Carbon event handler onto the
    /// main run loop; calling it off-main produces silent undelivered events.
    /// Reference: `third-party/spikes/s3-hotkey/src/main.rs`.
    pub fn register(hotkey: HotKey) -> Result<Self, Error> {
        let id = hotkey.id();
        let manager = GlobalHotKeyManager::new()?;
        manager.register(hotkey)?;
        tracing::info!(id, "registered global hotkey");
        Ok(Self {
            _manager: manager,
            _id: id,
        })
    }

    /// Subscribe to fire events.
    ///
    /// Returns the `'static` crossbeam receiver owned by the `global-hotkey`
    /// crate. The channel is a singleton — the same receiver is shared by
    /// every subscriber process-wide.
    ///
    /// **Thread:** safe to call from any thread. The returned receiver is
    /// `Send + Sync`. Block on it from a dedicated OS thread — `recv()` is a
    /// blocking syscall that would starve a cooperative tokio executor
    /// (CLAUDE.md §3 threading invariants; Loungy's 50ms polling in
    /// `hotkey.rs:96-98` is 8 frames at 120Hz — we do not copy that).
    pub fn on_fire() -> &'static GlobalHotKeyEventReceiver {
        GlobalHotKeyEvent::receiver()
    }
}
