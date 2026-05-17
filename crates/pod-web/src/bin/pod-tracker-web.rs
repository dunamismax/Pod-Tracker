use std::net::SocketAddr;

use anyhow::Context;
use pod_core::config::AppConfig;
use pod_web::telemetry;
use pod_web::{AppState, build_router};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();
    let config = AppConfig::from_env();
    telemetry::init(&config.environment);

    let bind_addr = config.bind_addr();
    let addr: SocketAddr = bind_addr
        .parse()
        .with_context(|| format!("parse POD_TRACKER_ADDR value {bind_addr:?}"))?;

    let db = pod_db::connect(config.database_url.as_deref())
        .await
        .context("connect database")?;

    let app = build_router(AppState::new(config.clone(), db));
    let listener = TcpListener::bind(addr)
        .await
        .with_context(|| format!("bind {addr}"))?;

    tracing::info!(
        %addr,
        environment = %config.environment,
        database_configured = config.database_configured(),
        "pod_tracker_web_starting"
    );

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("serve")
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

    tracing::info!("pod_tracker_web_stopping");
}
