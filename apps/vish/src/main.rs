//! vish UI process — NSApp run loop host, GPUI root, hotkey registrar, tray manager.

use std::cell::Cell;
use std::rc::Rc;

use anyhow::{Context as _, Result};
use global_hotkey::HotKeyState;
use global_hotkey::hotkey::{Code, HotKey, Modifiers};
use gpui::{
    AppContext, Bounds, Empty, WindowBackgroundAppearance, WindowKind, WindowOptions, px, size,
};
use objc2::MainThreadMarker;
use objc2_app_kit::{NSApplication, NSApplicationActivationPolicy};
use vish_macos::hotkey::Hotkey;
use vish_macos::{panel, vibrancy};

const WINDOW_WIDTH_PX: f32 = 800.0;
const WINDOW_HEIGHT_PX: f32 = 450.0;

fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    tracing::info!("vish starting");

    let mtm = MainThreadMarker::new().expect("vish main() runs on the main thread");

    let hotkey = HotKey::new(Some(Modifiers::ALT), Code::Space);
    let _hotkey = Hotkey::register(hotkey).context("register ⌥Space")?;

    let (tx, mut rx_async) =
        tokio::sync::mpsc::unbounded_channel::<global_hotkey::GlobalHotKeyEvent>();
    let rx_sync = Hotkey::on_fire().clone();
    std::thread::Builder::new()
        .name("vish-hotkey-bridge".into())
        .spawn(move || {
            while let Ok(ev) = rx_sync.recv() {
                if tx.send(ev).is_err() {
                    break;
                }
            }
        })
        .context("spawn vish-hotkey-bridge thread")?;

    gpui_platform::application().run(move |cx| {
        let app = NSApplication::sharedApplication(mtm);
        app.setActivationPolicy(NSApplicationActivationPolicy::Accessory);

        let bounds = Bounds::centered(None, size(px(WINDOW_WIDTH_PX), px(WINDOW_HEIGHT_PX)), cx);
        let options = WindowOptions {
            window_bounds: Some(gpui::WindowBounds::Windowed(bounds)),
            titlebar: None,
            kind: WindowKind::PopUp,
            is_movable: false,
            is_resizable: false,
            is_minimizable: false,
            focus: true,
            show: true,
            // Transparent so our NSVisualEffectView (applied by vibrancy::apply) is visible.
            // Opaque (default) makes GPUI paint its own backdrop over the vibrancy layer.
            window_background: WindowBackgroundAppearance::Transparent,
            ..Default::default()
        };

        let window_handle = match cx.open_window(options, |_window, cx| cx.new(|_| Empty)) {
            Ok(handle) => handle,
            Err(e) => {
                tracing::error!(error = %e, "open_window failed");
                cx.quit();
                return;
            }
        };

        let configure_result =
            cx.update_window(window_handle.into(), |_, window, _cx| -> Result<()> {
                panel::configure(window, panel::Options::default())?;
                vibrancy::apply(window)?;
                Ok(())
            });
        match configure_result {
            Err(e) => tracing::error!(error = %e, "window closed before configure"),
            Ok(Err(e)) => tracing::error!(error = %e, "panel/vibrancy configure failed"),
            Ok(Ok(())) => tracing::debug!("panel + vibrancy configured"),
        }

        let hidden = Rc::new(Cell::new(false));
        cx.spawn(async move |cx| {
            while let Some(ev) = rx_async.recv().await {
                if ev.state != HotKeyState::Pressed {
                    continue;
                }
                cx.update(|cx| {
                    if hidden.get() {
                        if let Err(e) =
                            window_handle.update(cx, |_, window, _| window.activate_window())
                        {
                            tracing::warn!(error = %e, "activate_window failed");
                            return;
                        }
                        hidden.set(false);
                    } else {
                        cx.hide();
                        hidden.set(true);
                    }
                });
            }
        })
        .detach();
    });

    Ok(())
}
