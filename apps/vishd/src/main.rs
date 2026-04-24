//! vishd indexer daemon — FSEvents, parsers, tantivy, sqlite. Runs as a LaunchAgent.

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    tracing::info!("vishd starting");
    Ok(())
}
