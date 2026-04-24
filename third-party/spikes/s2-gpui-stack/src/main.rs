//! S2+S4 compile probe. Proves the full UI-side dependency graph type-checks together.
//! Not a workspace member. Not a runtime test — exit before entering NSApp.

use objc2::rc::Retained;

fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    tracing::info!(spike = "s2+s4", zed_rev = "f7d46cf7", "compile probe");

    let _: Option<&gpui::Application> = None;
    let _: Option<&gpui_component::button::Button> = None;
    let _: Option<Retained<objc2_app_kit::NSApplication>> = None;
    let _: Option<Retained<objc2_foundation::NSString>> = None;
    let _queue: &'static dispatch2::DispatchQueue = dispatch2::DispatchQueue::main();

    Ok(())
}
