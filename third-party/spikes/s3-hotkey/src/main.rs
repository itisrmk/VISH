//! Phase 0 spike S3 — validate that `global-hotkey` registers ⌥Space on current macOS
//! without triggering an Accessibility permission prompt, and that events fire.

use anyhow::Result;
use global_hotkey::{
    GlobalHotKeyEvent, GlobalHotKeyManager,
    hotkey::{Code, HotKey, Modifiers},
};
use objc2::MainThreadMarker;
use objc2_app_kit::{NSApplication, NSApplicationActivationPolicy};

fn main() -> Result<()> {
    tracing_subscriber::fmt().init();

    let manager = GlobalHotKeyManager::new()?;
    let hotkey = HotKey::new(Some(Modifiers::ALT), Code::Space);
    manager.register(hotkey)?;
    tracing::info!(id = hotkey.id(), "registered ⌥Space");

    std::thread::spawn(|| {
        let rx = GlobalHotKeyEvent::receiver();
        while let Ok(ev) = rx.recv() {
            tracing::info!(id = ev.id, state = ?ev.state, "hotkey fired");
        }
    });

    let mtm = MainThreadMarker::new().expect("s3-hotkey main() runs on the main thread");
    let app = NSApplication::sharedApplication(mtm);
    app.setActivationPolicy(NSApplicationActivationPolicy::Accessory);
    tracing::info!("entering NSApp run loop — press ⌥Space, Ctrl-C to exit");
    app.run();

    drop(manager);
    Ok(())
}
