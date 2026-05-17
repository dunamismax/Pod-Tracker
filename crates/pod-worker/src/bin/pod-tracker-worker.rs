use std::time::Duration;

use anyhow::Context;
use pod_core::config::AppConfig;
use tokio::time;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();
    let config = AppConfig::from_env();
    init_tracing();

    let db = pod_db::connect(config.database_url.as_deref())
        .await
        .context("connect database")?;

    tracing::info!(
        environment = %config.environment,
        database_configured = config.database_configured(),
        "pod_tracker_worker_starting"
    );

    let mut ticker = time::interval(Duration::from_secs(5));
    loop {
        tokio::select! {
            _ = shutdown_signal() => {
                tracing::info!("pod_tracker_worker_stopping");
                return Ok(());
            }
            _ = ticker.tick() => {
                if let Some(pool) = db.as_ref()
                    && let Err(err) = pod_db::check_database(pool).await
                {
                    tracing::warn!(err = %err, "worker database check failed");
                }
            }
        }
    }
}

fn init_tracing() {
    let _ = tracing_subscriber::fmt()
        .json()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "pod_worker=info,pod_db=info".into()),
        )
        .try_init();
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}
