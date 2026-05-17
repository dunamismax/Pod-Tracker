use axum::extract::State;
use axum::http::header::{COOKIE, SET_COOKIE, USER_AGENT};
use axum::http::{HeaderMap, HeaderName, HeaderValue, StatusCode};
use axum::response::{Html, IntoResponse, Redirect, Response};
use axum::routing::{get, post};
use axum::{Form, Json, Router};
use pod_core::auth::{
    AuthError, SESSION_COOKIE_NAME, hash_password, hash_session_token, new_session_token,
    verify_password,
};
use pod_core::config::AppConfig;
use pod_core::health::{HealthResponse, ReadinessFailure};
use pod_core::playgroups::slugify;
use pod_db::{DbError, IdentityRepository, PlaygroupRepository, UserRecord};
use serde::Deserialize;
use sqlx::PgPool;
use time::{Duration, OffsetDateTime};
use tower_http::compression::CompressionLayer;
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::services::ServeDir;
use tower_http::trace::TraceLayer;

use crate::ui;

const CSRF_COOKIE_NAME: &str = "pod_tracker_csrf";
const SESSION_DURATION: Duration = Duration::days(30);

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
        .route("/signup", get(signup_form).post(signup))
        .route("/login", get(login_form).post(login))
        .route("/logout", post(logout))
        .route("/settings", get(settings))
        .route("/home", get(dashboard))
        .route("/playgroups", get(playgroups).post(create_playgroup))
        .route("/playgroups/{slug}", get(playgroup_detail))
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

async fn signup_form(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_signup(&csrf.token, None, "", ""),
        csrf.set_cookie,
    )
}

async fn signup(
    State(state): State<AppState>,
    headers: HeaderMap,
    Form(form): Form<SignupForm>,
) -> Response {
    if !csrf_valid(&headers, &form.csrf_token) {
        return StatusCode::BAD_REQUEST.into_response();
    }

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    let email = normalize_email(&form.email);
    let display_name = form.display_name.trim();

    if email.is_empty() || display_name.is_empty() || form.password.is_empty() {
        return html_with_cookies(
            StatusCode::UNPROCESSABLE_ENTITY,
            ui::render_signup(
                &csrf.token,
                Some("Email, display name, and password are required."),
                &email,
                display_name,
            ),
            csrf.set_cookie,
        );
    }

    let password_hash = match hash_password(&form.password) {
        Ok(hash) => hash,
        Err(AuthError::PasswordTooShort) => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_signup(
                    &csrf.token,
                    Some("Password must be at least 12 characters."),
                    &email,
                    display_name,
                ),
                csrf.set_cookie,
            );
        }
        Err(err) => {
            tracing::error!(err = %err, "hash signup password");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let repo = IdentityRepository::new(pool);
    let user = match repo.create_user(&email, display_name, &password_hash).await {
        Ok(user) => user,
        Err(err) if is_unique_violation(&err) => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_signup(
                    &csrf.token,
                    Some("An account already exists for that email."),
                    &email,
                    display_name,
                ),
                csrf.set_cookie,
            );
        }
        Err(err) => {
            tracing::error!(err = %err, "create user");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    match start_session(&state, &headers, user.id, pool).await {
        Ok(set_cookie) => redirect_with_cookies("/home", vec![set_cookie]),
        Err(err) => {
            tracing::error!(err = %err, "start signup session");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn login_form(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_login(&csrf.token, None, ""),
        csrf.set_cookie,
    )
}

async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Form(form): Form<LoginForm>,
) -> Response {
    if !csrf_valid(&headers, &form.csrf_token) {
        return StatusCode::BAD_REQUEST.into_response();
    }

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    let email = normalize_email(&form.email);

    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let repo = IdentityRepository::new(pool);
    let user = match repo.find_user_by_email(&email).await {
        Ok(Some(user)) if verify_password(&user.password_hash, &form.password) => user,
        Ok(_) => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_login(&csrf.token, Some("Email or password is incorrect."), &email),
                csrf.set_cookie,
            );
        }
        Err(err) => {
            tracing::error!(err = %err, "find login user");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    match start_session(&state, &headers, user.id, pool).await {
        Ok(set_cookie) => redirect_with_cookies("/home", vec![set_cookie]),
        Err(err) => {
            tracing::error!(err = %err, "start login session");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn logout(
    State(state): State<AppState>,
    headers: HeaderMap,
    Form(form): Form<CsrfForm>,
) -> Response {
    if !csrf_valid(&headers, &form.csrf_token) {
        return StatusCode::BAD_REQUEST.into_response();
    }

    if let Some(pool) = state.db.as_ref()
        && let Some(encoded) = cookie_value(&headers, SESSION_COOKIE_NAME)
        && let Ok(token_hash) = hash_session_token(&encoded)
    {
        let repo = IdentityRepository::new(pool);
        if let Err(err) = repo.revoke_session_by_token_hash(&token_hash).await {
            tracing::warn!(err = %err, "revoke session");
        }
    }

    redirect_with_cookies("/login", vec![expired_session_cookie(&state.config)])
}

async fn settings(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_settings(&user.email, &user.display_name, &csrf.token),
        csrf.set_cookie,
    )
}

async fn dashboard(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };

    let playgroups = match state.db.as_ref() {
        Some(pool) => match PlaygroupRepository::new(pool).list_for_user(user.id).await {
            Ok(playgroups) => playgroups,
            Err(err) => {
                tracing::error!(err = %err, "list dashboard playgroups");
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            }
        },
        None => Vec::new(),
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_dashboard(&user.display_name, &csrf.token, &playgroups),
        csrf.set_cookie,
    )
}

async fn playgroups(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };

    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let playgroups = match PlaygroupRepository::new(pool).list_for_user(user.id).await {
        Ok(playgroups) => playgroups,
        Err(err) => {
            tracing::error!(err = %err, "list playgroups");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_playgroups(&csrf.token, &playgroups, None, "", ""),
        csrf.set_cookie,
    )
}

async fn create_playgroup(
    State(state): State<AppState>,
    headers: HeaderMap,
    Form(form): Form<PlaygroupForm>,
) -> Response {
    if !csrf_valid(&headers, &form.csrf_token) {
        return StatusCode::BAD_REQUEST.into_response();
    }

    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let repo = PlaygroupRepository::new(pool);
    let csrf = ensure_csrf_cookie(&headers, &state.config);
    let name = form.name.trim();
    let description = form.description.trim();
    let playgroups = match repo.list_for_user(user.id).await {
        Ok(playgroups) => playgroups,
        Err(err) => {
            tracing::error!(err = %err, "list playgroups before create");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    if name.is_empty() {
        return html_with_cookies(
            StatusCode::UNPROCESSABLE_ENTITY,
            ui::render_playgroups(
                &csrf.token,
                &playgroups,
                Some("Playgroup name is required."),
                name,
                description,
            ),
            csrf.set_cookie,
        );
    }

    let slug = slugify(name);
    if slug.is_empty() {
        return html_with_cookies(
            StatusCode::UNPROCESSABLE_ENTITY,
            ui::render_playgroups(
                &csrf.token,
                &playgroups,
                Some("Playgroup name must include at least one letter or number."),
                name,
                description,
            ),
            csrf.set_cookie,
        );
    }

    match repo
        .create_playgroup(user.id, name, &slug, description)
        .await
    {
        Ok(_) => Redirect::to("/playgroups").into_response(),
        Err(err) if is_unique_violation(&err) => html_with_cookies(
            StatusCode::UNPROCESSABLE_ENTITY,
            ui::render_playgroups(
                &csrf.token,
                &playgroups,
                Some("A playgroup already uses that slug. Adjust the name and try again."),
                name,
                description,
            ),
            csrf.set_cookie,
        ),
        Err(err) => {
            tracing::error!(err = %err, "create playgroup");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn playgroup_detail(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(slug): axum::extract::Path<String>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let repo = PlaygroupRepository::new(pool);
    let playgroup = match repo.get_by_slug_for_user(&slug, user.id).await {
        Ok(Some(playgroup)) => playgroup,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get playgroup");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = pod_core::playgroups::PlaygroupRole::try_from(playgroup.role.as_str()).ok();
    let house_rules = match repo
        .list_house_rules(
            playgroup.id,
            role.is_some_and(pod_core::playgroups::PlaygroupRole::can_view_member_content),
        )
        .await
    {
        Ok(house_rules) => house_rules,
        Err(err) => {
            tracing::error!(err = %err, "list house rules");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let settings = match repo.get_settings(playgroup.id).await {
        Ok(settings) => settings,
        Err(err) => {
            tracing::error!(err = %err, "get playgroup settings");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    Html(ui::render_playgroup_detail(
        &playgroup,
        settings.as_ref(),
        &house_rules,
    ))
    .into_response()
}

async fn events() -> Html<String> {
    Html(ui::render_placeholder("Events"))
}

async fn observatory() -> Html<String> {
    Html(ui::render_placeholder("SQL Observatory"))
}

#[derive(Debug, Deserialize)]
struct SignupForm {
    email: String,
    display_name: String,
    password: String,
    csrf_token: String,
}

#[derive(Debug, Deserialize)]
struct LoginForm {
    email: String,
    password: String,
    csrf_token: String,
}

#[derive(Debug, Deserialize)]
struct CsrfForm {
    csrf_token: String,
}

#[derive(Debug, Deserialize)]
struct PlaygroupForm {
    name: String,
    description: String,
    csrf_token: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CsrfState {
    token: String,
    set_cookie: Vec<HeaderValue>,
}

async fn require_user(state: &AppState, headers: &HeaderMap) -> Option<UserRecord> {
    match load_current_user(state, headers).await {
        Ok(user) => user,
        Err(err) => {
            tracing::warn!(err = %err, "load current user");
            None
        }
    }
}

async fn load_current_user(
    state: &AppState,
    headers: &HeaderMap,
) -> Result<Option<UserRecord>, DbError> {
    let Some(pool) = state.db.as_ref() else {
        return Ok(None);
    };
    let Some(encoded) = cookie_value(headers, SESSION_COOKIE_NAME) else {
        return Ok(None);
    };
    let Ok(token_hash) = hash_session_token(&encoded) else {
        return Ok(None);
    };

    let repo = IdentityRepository::new(pool);
    let Some(session) = repo.find_active_session_by_token_hash(&token_hash).await? else {
        return Ok(None);
    };
    let _ = repo.touch_session(session.id).await?;

    repo.find_user_by_id(session.user_id).await
}

async fn start_session(
    state: &AppState,
    headers: &HeaderMap,
    user_id: uuid::Uuid,
    pool: &PgPool,
) -> Result<HeaderValue, DbError> {
    let session_token = new_session_token();
    let expires_at = OffsetDateTime::now_utc() + SESSION_DURATION;
    let user_agent = headers
        .get(USER_AGENT)
        .and_then(|value| value.to_str().ok());

    IdentityRepository::new(pool)
        .create_session(user_id, &session_token.hash, user_agent, expires_at)
        .await?;

    Ok(session_cookie(
        SESSION_COOKIE_NAME,
        &session_token.encoded,
        SESSION_DURATION.whole_seconds(),
        true,
        &state.config,
    ))
}

fn ensure_csrf_cookie(headers: &HeaderMap, config: &AppConfig) -> CsrfState {
    if let Some(token) = cookie_value(headers, CSRF_COOKIE_NAME) {
        return CsrfState {
            token,
            set_cookie: Vec::new(),
        };
    }

    let token = new_session_token().encoded;
    let set_cookie = vec![session_cookie(
        CSRF_COOKIE_NAME,
        &token,
        SESSION_DURATION.whole_seconds(),
        true,
        config,
    )];

    CsrfState { token, set_cookie }
}

fn csrf_valid(headers: &HeaderMap, form_token: &str) -> bool {
    cookie_value(headers, CSRF_COOKIE_NAME)
        .is_some_and(|cookie_token| !form_token.is_empty() && cookie_token == form_token)
}

fn normalize_email(email: &str) -> String {
    email.trim().to_lowercase()
}

fn cookie_value(headers: &HeaderMap, name: &str) -> Option<String> {
    let cookies = headers.get(COOKIE)?.to_str().ok()?;
    cookies.split(';').find_map(|cookie| {
        let (cookie_name, value) = cookie.trim().split_once('=')?;
        (cookie_name == name && !value.is_empty()).then(|| value.to_owned())
    })
}

fn session_cookie(
    name: &str,
    value: &str,
    max_age_seconds: i64,
    http_only: bool,
    config: &AppConfig,
) -> HeaderValue {
    let mut cookie = format!("{name}={value}; Path=/; SameSite=Lax; Max-Age={max_age_seconds}");
    if http_only {
        cookie.push_str("; HttpOnly");
    }
    if secure_cookies(config) {
        cookie.push_str("; Secure");
    }
    HeaderValue::from_str(&cookie).expect("valid cookie header")
}

fn expired_session_cookie(config: &AppConfig) -> HeaderValue {
    session_cookie(SESSION_COOKIE_NAME, "", 0, true, config)
}

fn secure_cookies(config: &AppConfig) -> bool {
    config.environment == "production"
}

fn html_with_cookies(status: StatusCode, html: String, set_cookies: Vec<HeaderValue>) -> Response {
    let mut response = (status, Html(html)).into_response();
    for set_cookie in set_cookies {
        response.headers_mut().append(SET_COOKIE, set_cookie);
    }
    response
}

fn redirect_with_cookies(location: &str, set_cookies: Vec<HeaderValue>) -> Response {
    let mut response = Redirect::to(location).into_response();
    for set_cookie in set_cookies {
        response.headers_mut().append(SET_COOKIE, set_cookie);
    }
    response
}

fn is_unique_violation(err: &DbError) -> bool {
    match err {
        DbError::Sqlx(sqlx::Error::Database(db_err)) => db_err.code().as_deref() == Some("23505"),
        _ => false,
    }
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

    let health = pod_db::HealthRepository::new(pool);
    if let Err(err) = health.ping().await {
        tracing::warn!(err = %err, "readiness check failed");
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(ReadinessFailure::not_ready("database")),
        )
            .into_response();
    }
    match health.first_missing_readiness_check().await {
        Ok(Some(check)) => {
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(ReadinessFailure::not_ready(check)),
            )
                .into_response();
        }
        Ok(None) => {}
        Err(err) => {
            tracing::warn!(err = %err, "readiness dependency check failed");
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(ReadinessFailure::not_ready("dependencies")),
            )
                .into_response();
        }
    }

    (StatusCode::OK, Json(HealthResponse::ready())).into_response()
}

#[cfg(test)]
mod tests {
    use axum::body::{Body, to_bytes};
    use axum::http::header::{CONTENT_TYPE, LOCATION, SET_COOKIE};
    use axum::http::{HeaderMap, Request, StatusCode};
    use pod_core::config::AppConfig;
    use tower::ServiceExt;

    use super::{AppState, build_router, session_cookie};

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

    fn test_state_with_db(pool: sqlx::PgPool) -> AppState {
        AppState::new(
            AppConfig {
                addr: "127.0.0.1:0".to_owned(),
                database_url: Some("postgres://example.test/pod_tracker".to_owned()),
                environment: "test".to_owned(),
                static_dir: "assets".to_owned(),
                smtp2go_api_key: None,
                smtp_sender: "pod-tracker@example.test".to_owned(),
            },
            Some(pool),
        )
    }

    async fn body_string(response: axum::response::Response) -> String {
        let bytes = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("body bytes");
        String::from_utf8(bytes.to_vec()).expect("utf8 body")
    }

    fn set_cookie_pair(headers: &HeaderMap, name: &str) -> String {
        headers
            .get_all(SET_COOKIE)
            .iter()
            .filter_map(|value| value.to_str().ok())
            .find(|value| value.starts_with(name))
            .and_then(|value| value.split(';').next())
            .expect("set-cookie pair")
            .to_owned()
    }

    fn cookie_value(cookie_pair: &str) -> &str {
        cookie_pair
            .split_once('=')
            .map(|(_, value)| value)
            .expect("cookie value")
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

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn readyz_requires_migrations_jobs_and_email_tables(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool));

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/readyz")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::OK);
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

    #[tokio::test]
    async fn signup_form_sets_csrf_cookie_and_hidden_token() {
        let app = build_router(test_state());

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/signup")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::OK);
        let csrf_cookie = set_cookie_pair(response.headers(), "pod_tracker_csrf=");
        let csrf_token = cookie_value(&csrf_cookie);
        let body = body_string(response).await;

        assert!(body.contains("Create account"));
        assert!(body.contains(&format!("value=\"{csrf_token}\"")));
    }

    #[tokio::test]
    async fn state_changing_auth_routes_reject_missing_csrf() {
        let app = build_router(test_state());

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/login")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .body(Body::from(
                        "email=player%40example.test&password=correcthorse&csrf_token=",
                    ))
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[test]
    fn session_cookie_uses_http_only_same_site_and_secure_in_production() {
        let mut config = test_state().config;
        config.environment = "production".to_owned();

        let cookie = session_cookie("pod_tracker_session", "abc", 60, true, &config)
            .to_str()
            .expect("cookie header")
            .to_owned();

        assert!(cookie.contains("HttpOnly"));
        assert!(cookie.contains("SameSite=Lax"));
        assert!(cookie.contains("Secure"));
        assert!(cookie.contains("Max-Age=60"));
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn signup_dashboard_and_logout_use_database_sessions(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool));

        let signup_form = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/signup")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("signup form");
        let csrf_cookie = set_cookie_pair(signup_form.headers(), "pod_tracker_csrf=");
        let csrf_token = cookie_value(&csrf_cookie).to_owned();

        let signup = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/signup")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", csrf_cookie.clone())
                    .body(Body::from(format!(
                        "email=player%40example.test&display_name=Player+One&password=correct-horse-battery&csrf_token={csrf_token}"
                    )))
                    .expect("request"),
            )
            .await
            .expect("signup");

        assert_eq!(signup.status(), StatusCode::SEE_OTHER);
        assert_eq!(signup.headers().get(LOCATION).expect("location"), "/home");
        let session_cookie = set_cookie_pair(signup.headers(), "pod_tracker_session=");
        let session_set_cookie = signup
            .headers()
            .get_all(SET_COOKIE)
            .iter()
            .filter_map(|value| value.to_str().ok())
            .find(|value| value.starts_with("pod_tracker_session="))
            .expect("session set-cookie");
        assert!(session_set_cookie.contains("HttpOnly"));
        assert!(session_set_cookie.contains("SameSite=Lax"));

        let cookie_header = format!("{csrf_cookie}; {session_cookie}");
        let dashboard = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/home")
                    .header("cookie", cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("dashboard");
        assert_eq!(dashboard.status(), StatusCode::OK);
        let dashboard_body = body_string(dashboard).await;
        assert!(dashboard_body.contains("Player One"));

        let logout = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/logout")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", cookie_header.clone())
                    .body(Body::from(format!("csrf_token={csrf_token}")))
                    .expect("request"),
            )
            .await
            .expect("logout");
        assert_eq!(logout.status(), StatusCode::SEE_OTHER);
        assert_eq!(logout.headers().get(LOCATION).expect("location"), "/login");

        let dashboard_after_logout = app
            .oneshot(
                Request::builder()
                    .uri("/home")
                    .header("cookie", cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("dashboard after logout");

        assert_eq!(dashboard_after_logout.status(), StatusCode::SEE_OTHER);
        assert_eq!(
            dashboard_after_logout
                .headers()
                .get(LOCATION)
                .expect("location"),
            "/login"
        );
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn authenticated_users_create_and_view_only_their_playgroups(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool));

        let owner_form = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/signup")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("owner signup form");
        let owner_csrf_cookie = set_cookie_pair(owner_form.headers(), "pod_tracker_csrf=");
        let owner_csrf_token = cookie_value(&owner_csrf_cookie).to_owned();

        let owner_signup = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/signup")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner_csrf_cookie.clone())
                    .body(Body::from(format!(
                        "email=owner%40example.test&display_name=Owner&password=correct-horse-battery&csrf_token={owner_csrf_token}"
                    )))
                    .expect("request"),
            )
            .await
            .expect("owner signup");
        let owner_session_cookie = set_cookie_pair(owner_signup.headers(), "pod_tracker_session=");
        let owner_cookie_header = format!("{owner_csrf_cookie}; {owner_session_cookie}");

        let create = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner_cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Friday+Night+Commander&description=Weekly+pods&csrf_token={owner_csrf_token}"
                    )))
                    .expect("request"),
            )
            .await
            .expect("create playgroup");
        assert_eq!(create.status(), StatusCode::SEE_OTHER);
        assert_eq!(
            create.headers().get(LOCATION).expect("location"),
            "/playgroups"
        );

        let owner_view = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/playgroups/friday-night-commander")
                    .header("cookie", owner_cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("owner view");
        assert_eq!(owner_view.status(), StatusCode::OK);
        let owner_body = body_string(owner_view).await;
        assert!(owner_body.contains("Friday Night Commander"));
        assert!(owner_body.contains("owner"));

        let outsider_form = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/signup")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("outsider signup form");
        let outsider_csrf_cookie = set_cookie_pair(outsider_form.headers(), "pod_tracker_csrf=");
        let outsider_csrf_token = cookie_value(&outsider_csrf_cookie).to_owned();

        let outsider_signup = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/signup")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", outsider_csrf_cookie.clone())
                    .body(Body::from(format!(
                        "email=outsider%40example.test&display_name=Outsider&password=correct-horse-battery&csrf_token={outsider_csrf_token}"
                    )))
                    .expect("request"),
            )
            .await
            .expect("outsider signup");
        let outsider_session_cookie =
            set_cookie_pair(outsider_signup.headers(), "pod_tracker_session=");
        let outsider_cookie_header = format!("{outsider_csrf_cookie}; {outsider_session_cookie}");

        let outsider_view = app
            .oneshot(
                Request::builder()
                    .uri("/playgroups/friday-night-commander")
                    .header("cookie", outsider_cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("outsider view");
        assert_eq!(outsider_view.status(), StatusCode::NOT_FOUND);
    }
}
