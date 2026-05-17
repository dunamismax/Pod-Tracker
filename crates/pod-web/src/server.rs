use axum::extract::State;
use axum::http::{HeaderName, StatusCode};
use axum::response::{Html, IntoResponse};
use axum::routing::get;
use axum::{Json, Router};
use pod_core::config::AppConfig;
use pod_core::health::{HealthResponse, ReadinessFailure};
use sqlx::PgPool;
use tower_http::compression::CompressionLayer;
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::services::ServeDir;
use tower_http::trace::TraceLayer;

use crate::ui;

#[derive(Clone)]
pub struct AppState {
    pub config: AppConfig,
    pub db: Option<PgPool>,
}

impl AppState {
    pub fn new(config: AppConfig, db: Option<PgPool>) -> Self {
        Self { config, db }
    }
}

pub fn build_router(state: AppState) -> Router {
    let request_id_header = HeaderName::from_static("x-request-id");

    Router::new()
        .route("/", get(home))
        .route("/about", get(about))
        .route("/roadmap", get(roadmap))
        .route("/status", get(status))
        .route("/home", get(dashboard))
        .route("/events", get(events))
        .route("/observatory", get(observatory))
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .nest_service("/static", ServeDir::new(state.config.static_dir.clone()))
        .with_state(state)
        .layer(CompressionLayer::new())
        .layer(PropagateRequestIdLayer::new(request_id_header.clone()))
        .layer(SetRequestIdLayer::new(request_id_header, MakeRequestUuid))
        .layer(TraceLayer::new_for_http())
}

async fn home() -> Html<String> {
    Html(ui::render_home())
}

async fn about() -> Html<String> {
    Html(ui::render_placeholder("About"))
}

async fn roadmap() -> Html<String> {
    Html(ui::render_placeholder("Roadmap"))
}

async fn dashboard() -> Html<String> {
    Html(ui::render_placeholder("Dashboard"))
}

async fn events() -> Html<String> {
    Html(ui::render_placeholder("Events"))
}

async fn observatory() -> Html<String> {
    Html(ui::render_placeholder("SQL Observatory"))
}

async fn status(State(state): State<AppState>) -> Html<String> {
    Html(ui::render_status(
        state.config.database_configured(),
        state.config.smtp_configured(),
    ))
}

async fn healthz() -> Json<HealthResponse> {
    Json(HealthResponse::ok())
}

async fn readyz(State(state): State<AppState>) -> impl IntoResponse {
    let Some(pool) = state.db.as_ref() else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(ReadinessFailure::not_ready("database_url")),
        )
            .into_response();
    };

    if let Err(err) = pod_db::check_database(pool).await {
        tracing::warn!(err = %err, "readiness check failed");
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(ReadinessFailure::not_ready("database")),
        )
            .into_response();
    }

    (StatusCode::OK, Json(HealthResponse::ready())).into_response()
}

#[cfg(test)]
mod tests {
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use pod_core::config::AppConfig;
    use tower::ServiceExt;

    use super::{AppState, build_router};

    fn test_state() -> AppState {
        AppState::new(
            AppConfig {
                addr: "127.0.0.1:0".to_owned(),
                database_url: None,
                environment: "test".to_owned(),
                static_dir: "assets".to_owned(),
                smtp2go_api_key: None,
                smtp_sender: "pod-tracker@example.test".to_owned(),
            },
            None,
        )
    }

    #[tokio::test]
    async fn healthz_reports_ok() {
        let app = build_router(test_state());

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/healthz")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn readyz_requires_database_configuration() {
        let app = build_router(test_state());

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/readyz")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test]
    async fn home_renders_server_html() {
        let app = build_router(test_state());

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::OK);
    }
}
