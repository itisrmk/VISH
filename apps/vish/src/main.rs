//! vish UI process — NSApp run loop host, GPUI root, hotkey registrar, tray manager.

fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    tracing::info!("vish starting");
    Ok(())
}
