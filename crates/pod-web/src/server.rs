use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::{Duration as StdDuration, Instant};

use axum::body::{Body, to_bytes};
use axum::extract::{Query, State};
use axum::http::header::{CONTENT_DISPOSITION, CONTENT_TYPE, COOKIE, SET_COOKIE, USER_AGENT};
use axum::http::{HeaderMap, HeaderName, HeaderValue, Method, Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{Html, IntoResponse, Redirect, Response};
use axum::routing::{get, post};
use axum::{Form, Json, Router};
use pod_core::auth::{
    AuthError, SESSION_COOKIE_NAME, hash_password, hash_session_token, new_session_token,
    verify_password,
};
use pod_core::collections::{
    CardCondition, CollectionVisibility, ProxyPrintEntry, WishlistPriority, export_proxy_print_list,
};
use pod_core::config::AppConfig;
use pod_core::decklists::{
    DecklistExportEntry, DecklistExportFormat, DecklistSection, export_decklist,
};
use pod_core::decks::{
    DeckStatus, DeckVisibility, TutorDensity, normalize_color_identity, normalize_tags,
};
use pod_core::events::{
    AddressVisibility, EventVisibility, RsvpStatus, can_manage_event, can_show_event_address,
};
use pod_core::games::{GameResultType, normalize_game_tags};
use pod_core::health::{HealthResponse, ReadinessFailure};
use pod_core::playgroups::{PlaygroupRole, slugify};
use pod_db::{
    AddCollectionCardInput, AddWishlistCardInput, AuditRepository, CardSearchFilters,
    CollectionRepository, CreateCollectionInput, CreateDeckInput, CreateEventInput,
    CreateWishlistInput, DbError, DeckRepository, DecklistImportInput, EventDeckDeclarationInput,
    EventDeckDeclarationWithDeck, EventLocationInput, EventRepository, EventRsvpRecord,
    EventWithRole, GameRepository, GameWithPlayers, IdentityRepository, LogGameInput,
    MetaRepository, PlaygroupRepository, PodRepository, PodWithSeats, RsvpInput,
    ScryfallRepository, UpdateEventInput, UserRecord,
};
use serde::Deserialize;
use sqlx::PgPool;
use time::{Date, Duration, Month, OffsetDateTime, PrimitiveDateTime, Time, UtcOffset};
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
    rate_limiter: Arc<RateLimiter>,
}

impl AppState {
    pub fn new(config: AppConfig, db: Option<PgPool>) -> Self {
        Self {
            config,
            db,
            rate_limiter: Arc::new(RateLimiter::default()),
        }
    }
}

pub fn build_router(state: AppState) -> Router {
    let request_id_header = HeaderName::from_static("x-request-id");
    let rate_limit_state = state.clone();

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
        .route("/playgroups/{slug}/events/new", get(new_event_form))
        .route("/playgroups/{slug}/events", post(create_event))
        .route("/events", get(events))
        .route("/events/{id}", get(event_detail))
        .route("/events/{id}/pods", get(event_pods))
        .route("/events/{id}/pods/generate", post(generate_event_pods))
        .route("/events/{id}/pods/publish", post(publish_event_pods))
        .route("/events/{id}/edit", get(edit_event_form).post(update_event))
        .route("/events/{id}/rsvp", post(save_user_rsvp))
        .route("/events/{id}/decks", post(declare_event_deck))
        .route("/events/{id}/games", post(log_event_game))
        .route("/pods/{id}/lock", post(lock_pod))
        .route("/pods/{id}/seats/{seat_id}/move", post(move_pod_seat))
        .route("/decks", get(decks).post(create_deck))
        .route("/decks/{id}", get(deck_detail))
        .route("/decks/{id}/import", post(import_decklist))
        .route("/decks/{id}/export/{format}", get(export_decklist_route))
        .route("/cards", get(cards))
        .route("/collections", get(collections).post(create_collection))
        .route("/collections/{id}", get(collection_detail))
        .route("/collections/{id}/cards", post(add_collection_card))
        .route(
            "/collections/{id}/decks/{deck_id}/missing",
            get(collection_missing_cards),
        )
        .route(
            "/collections/{id}/decks/{deck_id}/proxy-list",
            get(collection_proxy_list),
        )
        .route("/wishlists", get(wishlists).post(create_wishlist))
        .route("/wishlists/{id}", get(wishlist_detail))
        .route("/wishlists/{id}/cards", post(add_wishlist_card))
        .route(
            "/wishlists/{id}/collections/{collection_id}/missing",
            get(wishlist_missing_cards),
        )
        .route("/meta", get(meta_dashboard))
        .route("/e/{token}", get(public_event_detail))
        .route("/rsvp/{token}", get(guest_rsvp_form).post(save_guest_rsvp))
        .route("/calendar.ics", get(calendar_feed))
        .route("/observatory", get(observatory))
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .fallback(not_found)
        .nest_service("/static", ServeDir::new(state.config.static_dir.clone()))
        .with_state(state)
        .layer(CompressionLayer::new())
        .layer(PropagateRequestIdLayer::new(request_id_header.clone()))
        .layer(SetRequestIdLayer::new(request_id_header, MakeRequestUuid))
        .layer(
            TraceLayer::new_for_http().make_span_with(|request: &Request<Body>| {
                tracing::info_span!(
                    "http.request",
                    http.method = %request.method(),
                    http.route_family = route_family_label(request.method(), request.uri().path())
                )
            }),
        )
        .layer(middleware::from_fn(structured_error_pages))
        .layer(middleware::from_fn_with_state(
            rate_limit_state,
            enforce_rate_limit,
        ))
        .layer(middleware::from_fn(add_security_headers))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum RateLimitFamily {
    Signup,
    Login,
    Rsvp,
    Invite,
    DeckImport,
    Search,
    Admin,
}

impl RateLimitFamily {
    fn policy(self) -> RateLimitPolicy {
        match self {
            Self::Signup => RateLimitPolicy {
                max_requests: 5,
                window: StdDuration::from_secs(15 * 60),
            },
            Self::Login => RateLimitPolicy {
                max_requests: 10,
                window: StdDuration::from_secs(15 * 60),
            },
            Self::Rsvp => RateLimitPolicy {
                max_requests: 20,
                window: StdDuration::from_secs(10 * 60),
            },
            Self::Invite => RateLimitPolicy {
                max_requests: 60,
                window: StdDuration::from_secs(10 * 60),
            },
            Self::DeckImport => RateLimitPolicy {
                max_requests: 8,
                window: StdDuration::from_secs(15 * 60),
            },
            Self::Search => RateLimitPolicy {
                max_requests: 120,
                window: StdDuration::from_secs(60),
            },
            Self::Admin => RateLimitPolicy {
                max_requests: 30,
                window: StdDuration::from_secs(60),
            },
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Signup => "signup",
            Self::Login => "login",
            Self::Rsvp => "rsvp",
            Self::Invite => "invite",
            Self::DeckImport => "deck_import",
            Self::Search => "search",
            Self::Admin => "admin",
        }
    }
}

#[derive(Debug, Clone, Copy)]
struct RateLimitPolicy {
    max_requests: usize,
    window: StdDuration,
}

#[derive(Debug, Default)]
struct RateLimiter {
    attempts: Mutex<HashMap<(RateLimitFamily, String), VecDeque<Instant>>>,
}

impl RateLimiter {
    fn check(&self, family: RateLimitFamily, key: String) -> bool {
        let policy = family.policy();
        let now = Instant::now();
        let mut attempts = self.attempts.lock().expect("rate limiter lock");
        let bucket = attempts.entry((family, key)).or_default();

        while bucket
            .front()
            .is_some_and(|attempt| now.duration_since(*attempt) >= policy.window)
        {
            bucket.pop_front();
        }

        if bucket.len() >= policy.max_requests {
            return false;
        }

        bucket.push_back(now);
        true
    }
}

async fn enforce_rate_limit(
    State(state): State<AppState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    if let Some(family) = rate_limit_family(request.method(), request.uri().path()) {
        let key = client_rate_key(request.headers());
        if !state.rate_limiter.check(family, key.clone()) {
            tracing::warn!(
                rate_limit.family = family.as_str(),
                rate_limit.key = %key,
                "rate limit exceeded"
            );
            return error_response(
                StatusCode::TOO_MANY_REQUESTS,
                "Too many requests",
                "This action is temporarily limited. Wait a little before trying again.",
            );
        }
    }

    next.run(request).await
}

async fn structured_error_pages(request: Request<Body>, next: Next) -> Response {
    let response = next.run(request).await;
    let status = response.status();
    if !status.is_client_error() && !status.is_server_error() {
        return response;
    }
    if response.headers().contains_key(CONTENT_TYPE) {
        return response;
    }

    let (mut parts, body) = response.into_parts();
    let bytes = match to_bytes(body, 4096).await {
        Ok(bytes) => bytes,
        Err(err) => {
            tracing::warn!(err = %err, "read error response body");
            Default::default()
        }
    };
    if !bytes.is_empty() {
        return Response::from_parts(parts, Body::from(bytes));
    }

    let (title, message) = error_copy(status);
    parts.headers.insert(
        CONTENT_TYPE,
        HeaderValue::from_static("text/html; charset=utf-8"),
    );
    Response::from_parts(
        parts,
        Body::from(ui::render_error_page(status.as_u16(), title, message)),
    )
}

async fn not_found() -> Response {
    error_response(
        StatusCode::NOT_FOUND,
        "Page not found",
        "The requested page is not available.",
    )
}

fn rate_limit_family(method: &Method, path: &str) -> Option<RateLimitFamily> {
    match (method, path) {
        (&Method::POST, "/signup") => Some(RateLimitFamily::Signup),
        (&Method::POST, "/login") => Some(RateLimitFamily::Login),
        (&Method::GET, "/cards") | (&Method::GET, "/decks") => Some(RateLimitFamily::Search),
        _ if method == Method::POST && path.starts_with("/rsvp/") => Some(RateLimitFamily::Rsvp),
        _ if method == Method::GET && (path.starts_with("/rsvp/") || path.starts_with("/e/")) => {
            Some(RateLimitFamily::Invite)
        }
        _ if method == Method::POST && path.starts_with("/decks/") && path.ends_with("/import") => {
            Some(RateLimitFamily::DeckImport)
        }
        _ if method == Method::POST && is_admin_action_path(path) => Some(RateLimitFamily::Admin),
        _ => None,
    }
}

fn route_family_label(method: &Method, path: &str) -> &'static str {
    rate_limit_family(method, path)
        .map(RateLimitFamily::as_str)
        .unwrap_or_else(|| {
            if path == "/" {
                "home"
            } else if path.starts_with("/static/") {
                "static"
            } else if path == "/healthz" || path == "/readyz" || path == "/status" {
                "ops"
            } else if path.starts_with("/events/") {
                "events"
            } else if path.starts_with("/playgroups") {
                "playgroups"
            } else if path.starts_with("/decks/") {
                "decks"
            } else if path.starts_with("/collections") {
                "collections"
            } else if path.starts_with("/wishlists") {
                "wishlists"
            } else {
                "public"
            }
        })
}

fn is_admin_action_path(path: &str) -> bool {
    if path == "/playgroups" {
        return true;
    }

    let segments = path
        .trim_matches('/')
        .split('/')
        .filter(|segment| !segment.is_empty())
        .collect::<Vec<_>>();

    matches!(
        segments.as_slice(),
        ["playgroups", _, "events"]
            | ["events", _, "edit"]
            | ["events", _, "pods", "generate"]
            | ["events", _, "pods", "publish"]
            | ["events", _, "games"]
            | ["pods", _, "lock"]
            | ["pods", _, "seats", _, "move"]
    )
}

fn client_rate_key(headers: &HeaderMap) -> String {
    headers
        .get("x-forwarded-for")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.split(',').next())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .or_else(|| {
            headers
                .get("x-real-ip")
                .and_then(|value| value.to_str().ok())
                .map(str::trim)
                .filter(|value| !value.is_empty())
        })
        .unwrap_or("local")
        .to_owned()
}

fn error_copy(status: StatusCode) -> (&'static str, &'static str) {
    match status {
        StatusCode::BAD_REQUEST => ("Bad request", "The submitted request could not be used."),
        StatusCode::FORBIDDEN => ("Forbidden", "This account cannot perform that action."),
        StatusCode::NOT_FOUND => ("Page not found", "The requested page is not available."),
        StatusCode::TOO_MANY_REQUESTS => (
            "Too many requests",
            "This action is temporarily limited. Wait a little before trying again.",
        ),
        StatusCode::SERVICE_UNAVAILABLE => (
            "Service unavailable",
            "A required local dependency is not available right now.",
        ),
        _ if status.is_server_error() => (
            "Server error",
            "The application could not complete this request.",
        ),
        _ => (
            "Request failed",
            "The application could not complete this request.",
        ),
    }
}

fn error_response(status: StatusCode, title: &'static str, message: &'static str) -> Response {
    (
        status,
        Html(ui::render_error_page(status.as_u16(), title, message)),
    )
        .into_response()
}

async fn add_security_headers(request: Request<Body>, next: Next) -> Response {
    let mut response = next.run(request).await;
    let headers = response.headers_mut();
    headers.insert(
        HeaderName::from_static("x-content-type-options"),
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(
        HeaderName::from_static("referrer-policy"),
        HeaderValue::from_static("strict-origin-when-cross-origin"),
    );
    headers.insert(
        HeaderName::from_static("x-frame-options"),
        HeaderValue::from_static("DENY"),
    );
    headers.insert(
        HeaderName::from_static("content-security-policy"),
        HeaderValue::from_static(
            "default-src 'self'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'",
        ),
    );
    headers.insert(
        HeaderName::from_static("permissions-policy"),
        HeaderValue::from_static("camera=(), microphone=(), geolocation=()"),
    );
    response
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

async fn events(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let events = match EventRepository::new(pool).list_for_user(user.id).await {
        Ok(events) => events,
        Err(err) => {
            tracing::error!(err = %err, "list events");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    Html(ui::render_events(&events)).into_response()
}

async fn decks(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<DeckSearchQuery>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let deck_repo = DeckRepository::new(pool);
    let decks = match deck_repo.list_for_user(user.id, query.q.as_deref()).await {
        Ok(decks) => decks,
        Err(err) => {
            tracing::error!(err = %err, "list decks");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let playgroups = match PlaygroupRepository::new(pool).list_for_user(user.id).await {
        Ok(playgroups) => playgroups,
        Err(err) => {
            tracing::error!(err = %err, "list playgroups for deck form");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);

    html_with_cookies(
        StatusCode::OK,
        ui::render_decks(
            &csrf.token,
            &decks,
            &playgroups,
            query.q.as_deref().unwrap_or(""),
            None,
            None,
        ),
        csrf.set_cookie,
    )
}

async fn create_deck(
    State(state): State<AppState>,
    headers: HeaderMap,
    Form(form): Form<DeckForm>,
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

    let deck_repo = DeckRepository::new(pool);
    let playgroups = match PlaygroupRepository::new(pool).list_for_user(user.id).await {
        Ok(playgroups) => playgroups,
        Err(err) => {
            tracing::error!(err = %err, "list playgroups before deck create");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let existing_decks = match deck_repo.list_for_user(user.id, None).await {
        Ok(decks) => decks,
        Err(err) => {
            tracing::error!(err = %err, "list decks before create");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);
    let parsed = match parse_deck_form(&playgroups, &form) {
        Ok(input) => input,
        Err(message) => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_decks(
                    &csrf.token,
                    &existing_decks,
                    &playgroups,
                    "",
                    Some(message),
                    Some(&form),
                ),
                csrf.set_cookie,
            );
        }
    };

    let deck = match deck_repo
        .create_deck(CreateDeckInput {
            owner_user_id: user.id,
            playgroup_id: parsed.playgroup_id,
            name: &parsed.name,
            commander: &parsed.commander,
            color_identity: &parsed.color_identity,
            claimed_bracket: &parsed.claimed_bracket,
            archetype: &parsed.archetype,
            tags: &parsed.tags,
            visibility: &parsed.visibility,
            status: &parsed.status,
            game_changers_count: parsed.game_changers_count,
            has_infinite_combo: parsed.has_infinite_combo,
            has_fast_mana: parsed.has_fast_mana,
            tutor_density: &parsed.tutor_density,
            has_extra_turns: parsed.has_extra_turns,
            has_mass_land_denial: parsed.has_mass_land_denial,
            salt_notes: &parsed.salt_notes,
            notes: &parsed.notes,
        })
        .await
    {
        Ok(deck) => deck,
        Err(err) => {
            tracing::error!(err = %err, "create deck");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    Redirect::to(&format!("/decks/{}", deck.id)).into_response()
}

async fn deck_detail(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let deck_repo = DeckRepository::new(pool);
    let deck = match deck_repo.get_for_user(id, user.id).await {
        Ok(Some(deck)) => deck,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get deck");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let snapshot = match deck_repo
        .latest_bracket_snapshot_for_user(id, user.id)
        .await
    {
        Ok(snapshot) => snapshot,
        Err(err) => {
            tracing::error!(err = %err, "get latest deck bracket snapshot");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let recommendations = match deck_repo.similar_deck_recommendations(id, user.id, 4).await {
        Ok(recommendations) => recommendations,
        Err(err) => {
            tracing::error!(err = %err, "list similar deck recommendations");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_deck_detail(
            &deck,
            &csrf.token,
            snapshot.as_ref(),
            &recommendations,
            None,
            deck.owner_user_id == user.id && snapshot.is_some(),
        ),
        csrf.set_cookie,
    )
}

async fn import_decklist(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<DecklistImportForm>,
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

    let deck_repo = DeckRepository::new(pool);
    let deck = match deck_repo.get_for_user(id, user.id).await {
        Ok(Some(deck)) if deck.owner_user_id == user.id => deck,
        Ok(Some(_)) | Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get deck before import");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    if form.decklist.trim().is_empty() {
        let snapshot = match deck_repo
            .latest_bracket_snapshot_for_user(id, user.id)
            .await
        {
            Ok(snapshot) => snapshot,
            Err(err) => {
                tracing::error!(err = %err, "get latest deck bracket snapshot before import error");
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            }
        };
        return html_with_cookies(
            StatusCode::UNPROCESSABLE_ENTITY,
            ui::render_deck_detail(
                &deck,
                &csrf.token,
                snapshot.as_ref(),
                &[],
                Some("Paste a plain-text decklist before importing."),
                snapshot.is_some(),
            ),
            csrf.set_cookie,
        );
    }

    match deck_repo
        .import_plain_text_decklist(DecklistImportInput {
            deck_id: id,
            owner_user_id: user.id,
            source_text: form.decklist.trim(),
        })
        .await
    {
        Ok(Some(_summary)) => Redirect::to(&format!("/decks/{id}")).into_response(),
        Ok(None) => html_with_cookies(
            StatusCode::UNPROCESSABLE_ENTITY,
            ui::render_deck_detail(
                &deck,
                &csrf.token,
                None,
                &[],
                Some("No decklist cards were found to import."),
                false,
            ),
            csrf.set_cookie,
        ),
        Err(err) => {
            tracing::error!(err = %err, "import decklist");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn export_decklist_route(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path((id, format)): axum::extract::Path<(uuid::Uuid, String)>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let Some(format) = parse_export_format(&format) else {
        return StatusCode::NOT_FOUND.into_response();
    };

    let deck_repo = DeckRepository::new(pool);
    let export = match deck_repo
        .latest_decklist_export_for_owner(id, user.id)
        .await
    {
        Ok(Some(export)) => export,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "export decklist");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    if export.cards.is_empty() {
        return StatusCode::NOT_FOUND.into_response();
    }

    let entries = export
        .cards
        .iter()
        .map(|card| DecklistExportEntry {
            quantity: card.quantity,
            card_name: &card.card_name,
            matched_name: card.matched_name.as_deref(),
            section: decklist_section_from_db(&card.section),
            match_status: &card.match_status,
            is_commander: card.is_commander,
        })
        .collect::<Vec<_>>();
    let body = export_decklist(&entries, format);
    let filename = decklist_export_filename(&export.deck.name, format);

    let mut response = Response::new(Body::from(body));
    response.headers_mut().insert(
        CONTENT_TYPE,
        HeaderValue::from_static("text/plain; charset=utf-8"),
    );
    if let Ok(value) = HeaderValue::from_str(&format!("attachment; filename=\"{filename}\"")) {
        response.headers_mut().insert(CONTENT_DISPOSITION, value);
    }
    response
}

async fn cards(State(state): State<AppState>, Query(query): Query<CardSearchQuery>) -> Response {
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let color_identity = query
        .color_identity
        .as_deref()
        .map(normalize_color_identity)
        .unwrap_or_default();
    let color_filter = color_identity
        .chars()
        .map(|color| color.to_string())
        .collect::<Vec<_>>();
    let max_mana_value = query
        .max_mana_value
        .as_deref()
        .and_then(parse_optional_f64)
        .flatten();
    let max_usd = query
        .max_usd
        .as_deref()
        .and_then(parse_optional_f64)
        .flatten();

    let filters = CardSearchFilters {
        query: query.q.as_deref(),
        color_identity: (!color_filter.is_empty()).then_some(color_filter.as_slice()),
        commander_legal: query.commander_legal.as_deref().map(|_| true),
        min_mana_value: None,
        max_mana_value,
        type_line: query.type_line.as_deref(),
        max_usd,
        game_changer: query.game_changer.as_deref().map(|_| true),
        limit: Some(50),
    };

    let cards = match ScryfallRepository::new(pool).search_cards(filters).await {
        Ok(cards) => cards,
        Err(err) => {
            tracing::error!(err = %err, "search cards");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    Html(ui::render_cards(
        &cards,
        ui::CardSearchView {
            query: query.q.as_deref().unwrap_or(""),
            color_identity: &color_identity,
            commander_legal: query.commander_legal.is_some(),
            max_mana_value: query.max_mana_value.as_deref().unwrap_or(""),
            type_line: query.type_line.as_deref().unwrap_or(""),
            max_usd: query.max_usd.as_deref().unwrap_or(""),
            game_changer: query.game_changer.is_some(),
        },
    ))
    .into_response()
}

async fn collections(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let repo = CollectionRepository::new(pool);
    let collections = match repo.list_collections_for_user(user.id).await {
        Ok(collections) => collections,
        Err(err) => {
            tracing::error!(err = %err, "list collections");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let playgroups = match PlaygroupRepository::new(pool).list_for_user(user.id).await {
        Ok(playgroups) => playgroups,
        Err(err) => {
            tracing::error!(err = %err, "list playgroups for collection form");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);

    html_with_cookies(
        StatusCode::OK,
        ui::render_collections(&csrf.token, &collections, &playgroups, None, None),
        csrf.set_cookie,
    )
}

async fn create_collection(
    State(state): State<AppState>,
    headers: HeaderMap,
    Form(form): Form<CollectionForm>,
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

    let repo = CollectionRepository::new(pool);
    let playgroups = match PlaygroupRepository::new(pool).list_for_user(user.id).await {
        Ok(playgroups) => playgroups,
        Err(err) => {
            tracing::error!(err = %err, "list playgroups before collection create");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let existing = match repo.list_collections_for_user(user.id).await {
        Ok(collections) => collections,
        Err(err) => {
            tracing::error!(err = %err, "list collections before create");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);
    let parsed = match parse_collection_form(&playgroups, &form) {
        Ok(parsed) => parsed,
        Err(message) => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_collections(
                    &csrf.token,
                    &existing,
                    &playgroups,
                    Some(message),
                    Some(&form),
                ),
                csrf.set_cookie,
            );
        }
    };

    match repo
        .create_collection(CreateCollectionInput {
            owner_user_id: user.id,
            playgroup_id: parsed.playgroup_id,
            name: &parsed.name,
            visibility: &parsed.visibility,
            notes: &parsed.notes,
        })
        .await
    {
        Ok(Some(collection)) => {
            Redirect::to(&format!("/collections/{}", collection.id)).into_response()
        }
        Ok(None) => StatusCode::FORBIDDEN.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "create collection");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn collection_detail(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    render_collection_detail_response(&state, pool, user.id, id, None, &headers).await
}

async fn add_collection_card(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<CollectionCardForm>,
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
    let parsed = match parse_collection_card_form(&form) {
        Ok(parsed) => parsed,
        Err(message) => {
            return render_collection_detail_response(
                &state,
                pool,
                user.id,
                id,
                Some(message),
                &headers,
            )
            .await;
        }
    };

    let repo = CollectionRepository::new(pool);
    match repo
        .add_collection_card(AddCollectionCardInput {
            collection_id: id,
            owner_user_id: user.id,
            card_name: &parsed.card_name,
            set_code: parsed.set_code.as_deref(),
            collector_number: parsed.collector_number.as_deref(),
            quantity: parsed.quantity,
            foil: parsed.foil,
            condition: &parsed.condition,
            location: &parsed.location,
        })
        .await
    {
        Ok(Some(_card)) => Redirect::to(&format!("/collections/{id}")).into_response(),
        Ok(None) => {
            render_collection_detail_response(
                &state,
                pool,
                user.id,
                id,
                Some("Card was not found in the local Scryfall index or collection is not owned."),
                &headers,
            )
            .await
        }
        Err(err) => {
            tracing::error!(err = %err, "add collection card");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn collection_missing_cards(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path((id, deck_id)): axum::extract::Path<(uuid::Uuid, uuid::Uuid)>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let repo = CollectionRepository::new(pool);
    let collection = match repo.get_collection_for_user(id, user.id).await {
        Ok(Some(collection)) => collection,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get collection for missing cards");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let cards = match repo.missing_cards_for_deck(deck_id, id, user.id).await {
        Ok(cards) => cards,
        Err(err) => {
            tracing::error!(err = %err, "load missing cards");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    Html(ui::render_collection_missing_cards(
        &collection,
        deck_id,
        &cards,
    ))
    .into_response()
}

async fn collection_proxy_list(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path((id, deck_id)): axum::extract::Path<(uuid::Uuid, uuid::Uuid)>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let repo = CollectionRepository::new(pool);
    let collection = match repo.get_collection_for_user(id, user.id).await {
        Ok(Some(collection)) => collection,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get collection for proxy list");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let cards = match repo.missing_cards_for_deck(deck_id, id, user.id).await {
        Ok(cards) => cards,
        Err(err) => {
            tracing::error!(err = %err, "load proxy list cards");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let entries = cards
        .iter()
        .map(|card| ProxyPrintEntry {
            quantity: card.missing_quantity,
            card_name: &card.card_name,
            section: &card.section,
            is_commander: card.is_commander,
        })
        .collect::<Vec<_>>();
    let filename = text_export_filename(&collection.name, "proxy-list");

    let mut response = Response::new(Body::from(export_proxy_print_list(&entries)));
    response.headers_mut().insert(
        CONTENT_TYPE,
        HeaderValue::from_static("text/plain; charset=utf-8"),
    );
    if let Ok(value) = HeaderValue::from_str(&format!("attachment; filename=\"{filename}\"")) {
        response.headers_mut().insert(CONTENT_DISPOSITION, value);
    }
    response
}

async fn wishlists(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let repo = CollectionRepository::new(pool);
    let wishlists = match repo.list_wishlists_for_user(user.id).await {
        Ok(wishlists) => wishlists,
        Err(err) => {
            tracing::error!(err = %err, "list wishlists");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let playgroups = match PlaygroupRepository::new(pool).list_for_user(user.id).await {
        Ok(playgroups) => playgroups,
        Err(err) => {
            tracing::error!(err = %err, "list playgroups for wishlist form");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);

    html_with_cookies(
        StatusCode::OK,
        ui::render_wishlists(&csrf.token, &wishlists, &playgroups, None, None),
        csrf.set_cookie,
    )
}

async fn create_wishlist(
    State(state): State<AppState>,
    headers: HeaderMap,
    Form(form): Form<WishlistForm>,
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

    let repo = CollectionRepository::new(pool);
    let playgroups = match PlaygroupRepository::new(pool).list_for_user(user.id).await {
        Ok(playgroups) => playgroups,
        Err(err) => {
            tracing::error!(err = %err, "list playgroups before wishlist create");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let existing = match repo.list_wishlists_for_user(user.id).await {
        Ok(wishlists) => wishlists,
        Err(err) => {
            tracing::error!(err = %err, "list wishlists before create");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);
    let parsed = match parse_wishlist_form(&playgroups, &form) {
        Ok(parsed) => parsed,
        Err(message) => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_wishlists(
                    &csrf.token,
                    &existing,
                    &playgroups,
                    Some(message),
                    Some(&form),
                ),
                csrf.set_cookie,
            );
        }
    };

    match repo
        .create_wishlist(CreateWishlistInput {
            owner_user_id: user.id,
            playgroup_id: parsed.playgroup_id,
            name: &parsed.name,
            visibility: &parsed.visibility,
            notes: &parsed.notes,
        })
        .await
    {
        Ok(Some(wishlist)) => Redirect::to(&format!("/wishlists/{}", wishlist.id)).into_response(),
        Ok(None) => StatusCode::FORBIDDEN.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "create wishlist");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn wishlist_detail(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    render_wishlist_detail_response(&state, pool, user.id, id, None, &headers).await
}

async fn add_wishlist_card(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<WishlistCardForm>,
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
    let parsed = match parse_wishlist_card_form(&form) {
        Ok(parsed) => parsed,
        Err(message) => {
            return render_wishlist_detail_response(
                &state,
                pool,
                user.id,
                id,
                Some(message),
                &headers,
            )
            .await;
        }
    };

    let repo = CollectionRepository::new(pool);
    match repo
        .add_wishlist_card(AddWishlistCardInput {
            wishlist_id: id,
            owner_user_id: user.id,
            card_name: &parsed.card_name,
            desired_quantity: parsed.desired_quantity,
            priority: &parsed.priority,
            notes: &parsed.notes,
        })
        .await
    {
        Ok(Some(_card)) => Redirect::to(&format!("/wishlists/{id}")).into_response(),
        Ok(None) => {
            render_wishlist_detail_response(
                &state,
                pool,
                user.id,
                id,
                Some("Card was not found in the local Scryfall index or wishlist is not owned."),
                &headers,
            )
            .await
        }
        Err(err) => {
            tracing::error!(err = %err, "add wishlist card");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn wishlist_missing_cards(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path((id, collection_id)): axum::extract::Path<(uuid::Uuid, uuid::Uuid)>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let repo = CollectionRepository::new(pool);
    let wishlist = match repo.get_wishlist_for_user(id, user.id).await {
        Ok(Some(wishlist)) => wishlist,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get wishlist for missing cards");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let collection = match repo.get_collection_for_user(collection_id, user.id).await {
        Ok(Some(collection)) => collection,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get collection for wishlist missing cards");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let cards = match repo
        .missing_wishlist_cards_for_collection(id, collection_id, user.id)
        .await
    {
        Ok(cards) => cards,
        Err(err) => {
            tracing::error!(err = %err, "load wishlist missing cards");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    Html(ui::render_wishlist_missing_cards(
        &wishlist,
        &collection,
        &cards,
    ))
    .into_response()
}

async fn meta_dashboard(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let dashboard = match MetaRepository::new(pool).dashboard_for_user(user.id).await {
        Ok(dashboard) => dashboard,
        Err(err) => {
            tracing::error!(err = %err, "load meta dashboard");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    Html(ui::render_meta_dashboard(&dashboard)).into_response()
}

async fn new_event_form(
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
            tracing::error!(err = %err, "get playgroup for new event");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(playgroup.role.as_str()).ok();
    if !role.is_some_and(can_manage_event) {
        return StatusCode::FORBIDDEN.into_response();
    }

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_event_form(&playgroup, &csrf.token, None, None),
        csrf.set_cookie,
    )
}

async fn create_event(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(slug): axum::extract::Path<String>,
    Form(form): Form<EventForm>,
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

    let playgroup_repo = PlaygroupRepository::new(pool);
    let playgroup = match playgroup_repo.get_by_slug_for_user(&slug, user.id).await {
        Ok(Some(playgroup)) => playgroup,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get playgroup for create event");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(playgroup.role.as_str()).ok();
    if !role.is_some_and(can_manage_event) {
        return StatusCode::FORBIDDEN.into_response();
    }

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    let title = form.title.trim();
    let description = form.description.trim();
    let visibility = match EventVisibility::try_from(form.visibility.trim()) {
        Ok(visibility) => visibility,
        Err(()) => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_event_form(
                    &playgroup,
                    &csrf.token,
                    Some("Choose a valid event visibility."),
                    Some(&form),
                ),
                csrf.set_cookie,
            );
        }
    };
    let address_visibility = match AddressVisibility::try_from(form.address_visibility.trim()) {
        Ok(visibility) => visibility,
        Err(()) => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_event_form(
                    &playgroup,
                    &csrf.token,
                    Some("Choose a valid address visibility."),
                    Some(&form),
                ),
                csrf.set_cookie,
            );
        }
    };
    let start_time = match parse_datetime_local(&form.start_time) {
        Some(start_time) if !title.is_empty() => start_time,
        _ => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_event_form(
                    &playgroup,
                    &csrf.token,
                    Some("Title and start time are required."),
                    Some(&form),
                ),
                csrf.set_cookie,
            );
        }
    };
    let end_time = parse_optional_datetime_local(&form.end_time);
    let location_name = form.location_name.trim();
    let location = (!location_name.is_empty()).then(|| EventLocationInput {
        name: location_name,
        address_line1: optional_trimmed(&form.address_line1),
        address_line2: optional_trimmed(&form.address_line2),
        city: optional_trimmed(&form.city),
        state_province: optional_trimmed(&form.state_province),
        postal_code: optional_trimmed(&form.postal_code),
        country: optional_trimmed(&form.country),
        notes: form.location_notes.trim(),
    });

    let invite_token = new_public_token();
    let event = match EventRepository::new(pool)
        .create_event(CreateEventInput {
            playgroup_id: playgroup.id,
            title,
            description,
            start_time,
            end_time,
            location,
            visibility: visibility.as_str(),
            invite_token: &invite_token,
            address_visibility: address_visibility.as_str(),
            created_by: user.id,
        })
        .await
    {
        Ok(event) => event,
        Err(err) => {
            tracing::error!(err = %err, "create event");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    Redirect::to(&format!("/events/{}", event.id)).into_response()
}

async fn event_detail(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let repo = EventRepository::new(pool);
    let event = match repo.get_for_user(id, user.id).await {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let mut context = match event_page_context(pool, &repo, &event, Some(user.id), false).await {
        Ok(context) => context,
        Err(err) => {
            tracing::error!(err = %err, "load event context");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let deck_repo = DeckRepository::new(pool);
    context.deck_declarations = match deck_repo.list_event_declarations(event.id).await {
        Ok(declarations) => declarations,
        Err(err) => {
            tracing::error!(err = %err, "list event deck declarations");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    context.user_decks = match deck_repo.list_owned_active_for_user(user.id).await {
        Ok(decks) => decks,
        Err(err) => {
            tracing::error!(err = %err, "list user decks for event declaration");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    context.pods = match PodRepository::new(pool).list_for_event(event.id).await {
        Ok(pods) => pods,
        Err(err) => {
            tracing::error!(err = %err, "list pods for event detail");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    context.games = match GameRepository::new(pool).list_for_event(event.id).await {
        Ok(games) => games,
        Err(err) => {
            tracing::error!(err = %err, "list games for event detail");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_event_detail(&event, &context, &csrf.token),
        csrf.set_cookie,
    )
}

async fn event_pods(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let event = match EventRepository::new(pool).get_for_user(id, user.id).await {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event pods");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(event.member_role.as_str()).ok();
    let pods = match PodRepository::new(pool).list_for_event(event.id).await {
        Ok(pods) => pods,
        Err(err) => {
            tracing::error!(err = %err, "list event pods");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);

    html_with_cookies(
        StatusCode::OK,
        ui::render_event_pods(
            &event,
            &pods,
            &csrf.token,
            role.is_some_and(can_manage_event),
        ),
        csrf.set_cookie,
    )
}

async fn generate_event_pods(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<CsrfForm>,
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
    let event = match EventRepository::new(pool).get_for_user(id, user.id).await {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event before pod generation");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(event.member_role.as_str()).ok();
    if !role.is_some_and(can_manage_event) {
        return StatusCode::FORBIDDEN.into_response();
    }

    match PodRepository::new(pool)
        .generate_candidate_pods(id, 4)
        .await
    {
        Ok(_) => Redirect::to(&format!("/events/{id}/pods")).into_response(),
        Err(err) => {
            tracing::error!(err = %err, "generate event pods");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn publish_event_pods(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<CsrfForm>,
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
    let event = match EventRepository::new(pool).get_for_user(id, user.id).await {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event before pod publish");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(event.member_role.as_str()).ok();
    if !role.is_some_and(can_manage_event) {
        return StatusCode::FORBIDDEN.into_response();
    }

    match PodRepository::new(pool).publish_event_pods(id).await {
        Ok(_) => Redirect::to(&format!("/events/{id}/pods")).into_response(),
        Err(err) => {
            tracing::error!(err = %err, "publish event pods");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn lock_pod(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<CsrfForm>,
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
    let pod_repo = PodRepository::new(pool);
    let event_id = match pod_repo.event_id_for_pod(id).await {
        Ok(Some(event_id)) => event_id,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get pod event before lock");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let event = match EventRepository::new(pool)
        .get_for_user(event_id, user.id)
        .await
    {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event before pod lock");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(event.member_role.as_str()).ok();
    if !role.is_some_and(can_manage_event) {
        return StatusCode::FORBIDDEN.into_response();
    }

    match pod_repo.lock_pod(id).await {
        Ok(Some(_)) => Redirect::to(&format!("/events/{event_id}/pods")).into_response(),
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "lock pod");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn move_pod_seat(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path((id, seat_id)): axum::extract::Path<(uuid::Uuid, uuid::Uuid)>,
    Form(form): Form<PodMoveForm>,
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
    let pod_repo = PodRepository::new(pool);
    let event_id = match pod_repo.event_id_for_pod(id).await {
        Ok(Some(event_id)) => event_id,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get pod event before move");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let event = match EventRepository::new(pool)
        .get_for_user(event_id, user.id)
        .await
    {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event before seat move");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(event.member_role.as_str()).ok();
    if !role.is_some_and(can_manage_event) {
        return StatusCode::FORBIDDEN.into_response();
    }

    let target_pod_id = match form.target_pod_id.parse() {
        Ok(id) => id,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };
    let seat_position = parse_optional_i32(&form.seat_position)
        .unwrap_or(None)
        .filter(|position| *position > 0);
    let Some(seat_position) = seat_position else {
        return StatusCode::BAD_REQUEST.into_response();
    };

    match pod_repo
        .move_seat(seat_id, target_pod_id, seat_position)
        .await
    {
        Ok(Some(_)) => Redirect::to(&format!("/events/{event_id}/pods")).into_response(),
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "move pod seat");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn edit_event_form(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let event = match EventRepository::new(pool).get_for_user(id, user.id).await {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event for edit");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(event.member_role.as_str()).ok();
    if !role.is_some_and(can_manage_event) {
        return StatusCode::FORBIDDEN.into_response();
    }

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_event_edit(&event, &csrf.token, None, None),
        csrf.set_cookie,
    )
}

async fn update_event(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<EventEditForm>,
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
    let repo = EventRepository::new(pool);
    let event = match repo.get_for_user(id, user.id).await {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event before update");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(event.member_role.as_str()).ok();
    if !role.is_some_and(can_manage_event) {
        return StatusCode::FORBIDDEN.into_response();
    }

    let csrf = ensure_csrf_cookie(&headers, &state.config);
    let title = form.title.trim();
    let visibility = match EventVisibility::try_from(form.visibility.trim()) {
        Ok(visibility) => visibility,
        Err(()) => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_event_edit(
                    &event,
                    &csrf.token,
                    Some("Choose a valid event visibility."),
                    Some(&form),
                ),
                csrf.set_cookie,
            );
        }
    };
    let start_time = match parse_datetime_local(&form.start_time) {
        Some(start_time) if !title.is_empty() => start_time,
        _ => {
            return html_with_cookies(
                StatusCode::UNPROCESSABLE_ENTITY,
                ui::render_event_edit(
                    &event,
                    &csrf.token,
                    Some("Title and start time are required."),
                    Some(&form),
                ),
                csrf.set_cookie,
            );
        }
    };

    match repo
        .update_event(UpdateEventInput {
            id: event.id,
            title,
            description: form.description.trim(),
            start_time,
            end_time: parse_optional_datetime_local(&form.end_time),
            visibility: visibility.as_str(),
        })
        .await
    {
        Ok(event) => Redirect::to(&format!("/events/{}", event.id)).into_response(),
        Err(err) => {
            tracing::error!(err = %err, "update event");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn save_user_rsvp(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<RsvpForm>,
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
    let repo = EventRepository::new(pool);
    match repo.get_for_user(id, user.id).await {
        Ok(Some(_)) => {}
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event before rsvp");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    }
    let rsvp = match parse_rsvp_input(id, Some(user.id), None, &form) {
        Ok(rsvp) => rsvp,
        Err(()) => return StatusCode::BAD_REQUEST.into_response(),
    };
    if let Err(err) = repo.upsert_user_rsvp(rsvp).await {
        tracing::error!(err = %err, "save user rsvp");
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    Redirect::to(&format!("/events/{id}")).into_response()
}

async fn declare_event_deck(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<DeckDeclarationForm>,
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

    match EventRepository::new(pool).get_for_user(id, user.id).await {
        Ok(Some(_)) => {}
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event before deck declaration");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    }
    let preference = parse_optional_i32(&form.preference)
        .unwrap_or(Some(1))
        .filter(|preference| (1..=5).contains(preference));
    let Some(preference) = preference else {
        return StatusCode::BAD_REQUEST.into_response();
    };
    let deck_id = match form.deck_id.parse() {
        Ok(deck_id) => deck_id,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };

    match DeckRepository::new(pool)
        .declare_event_deck(EventDeckDeclarationInput {
            event_id: id,
            user_id: user.id,
            deck_id,
            preference,
            testing_notes: form.testing_notes.trim(),
        })
        .await
    {
        Ok(Some(_)) => Redirect::to(&format!("/events/{id}")).into_response(),
        Ok(None) => StatusCode::FORBIDDEN.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "declare event deck");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn log_event_game(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(id): axum::extract::Path<uuid::Uuid>,
    Form(form): Form<GameLogForm>,
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
    let event = match EventRepository::new(pool).get_for_user(id, user.id).await {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get event before game log");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let role = PlaygroupRole::try_from(event.member_role.as_str()).ok();
    if !role.is_some_and(can_manage_event) {
        return StatusCode::FORBIDDEN.into_response();
    }

    let result_type = match GameResultType::try_from(form.result_type.trim()) {
        Ok(result_type) => result_type,
        Err(()) => return StatusCode::BAD_REQUEST.into_response(),
    };
    let pod_id = match form.pod_id.parse() {
        Ok(pod_id) => pod_id,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };
    let winner_user_id = match optional_trimmed(&form.winner_user_id)
        .map(str::parse)
        .transpose()
    {
        Ok(winner_user_id) => winner_user_id,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };
    if result_type.needs_winner() && winner_user_id.is_none() {
        return StatusCode::BAD_REQUEST.into_response();
    }
    let first_player_user_id = match optional_trimmed(&form.first_player_user_id)
        .map(str::parse)
        .transpose()
    {
        Ok(first_player_user_id) => first_player_user_id,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };
    let elimination_order_user_ids = match parse_elimination_order(&form) {
        Ok(user_ids) => user_ids,
        Err(()) => return StatusCode::BAD_REQUEST.into_response(),
    };
    let turn_count = parse_optional_i32(&form.turn_count)
        .unwrap_or(None)
        .filter(|turns| *turns > 0);
    let duration_minutes = parse_optional_i32(&form.duration_minutes)
        .unwrap_or(None)
        .filter(|minutes| *minutes > 0);
    let tags = normalize_game_tags(&form.tags);
    let winning_team = optional_trimmed(&form.winning_team);

    match GameRepository::new(pool)
        .log_game_from_pod(LogGameInput {
            event_id: id,
            pod_id,
            logged_by_user_id: user.id,
            result_type: result_type.as_str(),
            winner_user_id,
            turn_count,
            duration_minutes,
            first_player_user_id,
            elimination_order_user_ids: &elimination_order_user_ids,
            tags: &tags,
            notes: form.notes.trim(),
            winning_team,
            complete_event: form.complete_event,
        })
        .await
    {
        Ok(Some(_)) => Redirect::to(&format!("/events/{id}")).into_response(),
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "log game");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

async fn public_event_detail(
    State(state): State<AppState>,
    axum::extract::Path(token): axum::extract::Path<String>,
) -> Response {
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let repo = EventRepository::new(pool);
    let event = match repo.get_public_safe_by_token(token.trim()).await {
        Ok(Some(event)) => event,
        Ok(_) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get public event");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let context = match public_event_page_context(pool, &repo, event.id, "public_event").await {
        Ok(context) => context,
        Err(err) => {
            tracing::error!(err = %err, "load public event context");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    Html(ui::render_public_event(&event, &context)).into_response()
}

async fn guest_rsvp_form(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(token): axum::extract::Path<String>,
) -> Response {
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let repo = EventRepository::new(pool);
    let event = match repo.get_by_token(token.trim()).await {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get guest rsvp event");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let context = match public_event_page_context(pool, &repo, event.id, "guest_rsvp_form").await {
        Ok(context) => context,
        Err(err) => {
            tracing::error!(err = %err, "load guest rsvp context");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let csrf = ensure_csrf_cookie(&headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_guest_rsvp(&event, &context, &csrf.token, None, None),
        csrf.set_cookie,
    )
}

async fn save_guest_rsvp(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(token): axum::extract::Path<String>,
    Form(form): Form<RsvpForm>,
) -> Response {
    if !csrf_valid(&headers, &form.csrf_token) {
        return StatusCode::BAD_REQUEST.into_response();
    }
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let repo = EventRepository::new(pool);
    let event = match repo.get_by_token(token.trim()).await {
        Ok(Some(event)) => event,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get guest rsvp event before save");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let guest_name = form.guest_name.trim();
    if guest_name.is_empty() {
        let context =
            match public_event_page_context(pool, &repo, event.id, "guest_rsvp_error").await {
                Ok(context) => context,
                Err(err) => {
                    tracing::error!(err = %err, "reload guest rsvp context");
                    return StatusCode::INTERNAL_SERVER_ERROR.into_response();
                }
            };
        let csrf = ensure_csrf_cookie(&headers, &state.config);
        return html_with_cookies(
            StatusCode::UNPROCESSABLE_ENTITY,
            ui::render_guest_rsvp(
                &event,
                &context,
                &csrf.token,
                Some("Name and a valid RSVP status are required."),
                Some(&form),
            ),
            csrf.set_cookie,
        );
    }
    let rsvp = match parse_rsvp_input(event.id, None, Some(guest_name), &form) {
        Ok(rsvp) => rsvp,
        Err(()) => return StatusCode::BAD_REQUEST.into_response(),
    };
    if let Err(err) = repo.create_rsvp(rsvp).await {
        tracing::error!(err = %err, "save guest rsvp");
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    Redirect::to(&format!("/rsvp/{token}?saved=1")).into_response()
}

async fn calendar_feed(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = require_user(&state, &headers).await else {
        return Redirect::to("/login").into_response();
    };
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    let events = match EventRepository::new(pool)
        .list_calendar_events(user.id)
        .await
    {
        Ok(events) => events,
        Err(err) => {
            tracing::error!(err = %err, "calendar events");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let calendar = render_calendar(&events);
    (
        [
            (CONTENT_TYPE, "text/calendar; charset=utf-8"),
            (CONTENT_DISPOSITION, "inline; filename=\"pod-tracker.ics\""),
        ],
        calendar,
    )
        .into_response()
}

async fn observatory() -> Html<String> {
    Html(ui::render_observatory())
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

#[derive(Debug, Deserialize)]
struct DeckSearchQuery {
    q: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CardSearchQuery {
    q: Option<String>,
    color_identity: Option<String>,
    commander_legal: Option<String>,
    max_mana_value: Option<String>,
    type_line: Option<String>,
    max_usd: Option<String>,
    game_changer: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct CollectionForm {
    pub(crate) name: String,
    #[serde(default)]
    pub(crate) visibility: String,
    #[serde(default)]
    pub(crate) playgroup_id: String,
    #[serde(default)]
    pub(crate) notes: String,
    pub(crate) csrf_token: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct CollectionCardForm {
    pub(crate) card_name: String,
    #[serde(default)]
    pub(crate) set_code: String,
    #[serde(default)]
    pub(crate) collector_number: String,
    #[serde(default)]
    pub(crate) quantity: String,
    #[serde(default)]
    pub(crate) foil: bool,
    #[serde(default)]
    pub(crate) condition: String,
    #[serde(default)]
    pub(crate) location: String,
    pub(crate) csrf_token: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct WishlistForm {
    pub(crate) name: String,
    #[serde(default)]
    pub(crate) visibility: String,
    #[serde(default)]
    pub(crate) playgroup_id: String,
    #[serde(default)]
    pub(crate) notes: String,
    pub(crate) csrf_token: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct WishlistCardForm {
    pub(crate) card_name: String,
    #[serde(default)]
    pub(crate) desired_quantity: String,
    #[serde(default)]
    pub(crate) priority: String,
    #[serde(default)]
    pub(crate) notes: String,
    pub(crate) csrf_token: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct DeckForm {
    pub(crate) name: String,
    pub(crate) commander: String,
    #[serde(default)]
    pub(crate) color_identity: String,
    #[serde(default)]
    pub(crate) claimed_bracket: String,
    #[serde(default)]
    pub(crate) archetype: String,
    #[serde(default)]
    pub(crate) tags: String,
    #[serde(default)]
    pub(crate) visibility: String,
    #[serde(default)]
    pub(crate) playgroup_id: String,
    #[serde(default)]
    pub(crate) status: String,
    #[serde(default)]
    pub(crate) game_changers_count: String,
    #[serde(default)]
    pub(crate) has_infinite_combo: bool,
    #[serde(default)]
    pub(crate) has_fast_mana: bool,
    #[serde(default)]
    pub(crate) tutor_density: String,
    #[serde(default)]
    pub(crate) has_extra_turns: bool,
    #[serde(default)]
    pub(crate) has_mass_land_denial: bool,
    #[serde(default)]
    pub(crate) salt_notes: String,
    #[serde(default)]
    pub(crate) notes: String,
    pub(crate) csrf_token: String,
}

#[derive(Debug, Deserialize)]
struct DecklistImportForm {
    decklist: String,
    csrf_token: String,
}

#[derive(Debug, Deserialize)]
struct DeckDeclarationForm {
    deck_id: String,
    #[serde(default)]
    preference: String,
    #[serde(default)]
    testing_notes: String,
    csrf_token: String,
}

#[derive(Debug, Deserialize)]
struct PodMoveForm {
    target_pod_id: String,
    seat_position: String,
    csrf_token: String,
}

#[derive(Debug, Deserialize)]
struct GameLogForm {
    pod_id: String,
    result_type: String,
    #[serde(default)]
    winner_user_id: String,
    #[serde(default)]
    turn_count: String,
    #[serde(default)]
    duration_minutes: String,
    #[serde(default)]
    first_player_user_id: String,
    #[serde(default)]
    elimination_1_user_id: String,
    #[serde(default)]
    elimination_2_user_id: String,
    #[serde(default)]
    elimination_3_user_id: String,
    #[serde(default)]
    elimination_4_user_id: String,
    #[serde(default)]
    elimination_5_user_id: String,
    #[serde(default)]
    winning_team: String,
    #[serde(default)]
    tags: String,
    #[serde(default)]
    notes: String,
    #[serde(default)]
    complete_event: bool,
    csrf_token: String,
}

#[derive(Debug, Clone)]
struct ParsedDeckForm {
    playgroup_id: Option<uuid::Uuid>,
    name: String,
    commander: String,
    color_identity: String,
    claimed_bracket: String,
    archetype: String,
    tags: Vec<String>,
    visibility: String,
    status: String,
    game_changers_count: i32,
    has_infinite_combo: bool,
    has_fast_mana: bool,
    tutor_density: String,
    has_extra_turns: bool,
    has_mass_land_denial: bool,
    salt_notes: String,
    notes: String,
}

#[derive(Debug, Clone)]
struct ParsedCollectionForm {
    playgroup_id: Option<uuid::Uuid>,
    name: String,
    visibility: String,
    notes: String,
}

#[derive(Debug, Clone)]
struct ParsedCollectionCardForm {
    card_name: String,
    set_code: Option<String>,
    collector_number: Option<String>,
    quantity: i32,
    foil: bool,
    condition: String,
    location: String,
}

#[derive(Debug, Clone)]
struct ParsedWishlistForm {
    playgroup_id: Option<uuid::Uuid>,
    name: String,
    visibility: String,
    notes: String,
}

#[derive(Debug, Clone)]
struct ParsedWishlistCardForm {
    card_name: String,
    desired_quantity: i32,
    priority: String,
    notes: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct EventForm {
    pub(crate) title: String,
    pub(crate) description: String,
    pub(crate) start_time: String,
    #[serde(default)]
    pub(crate) end_time: String,
    pub(crate) visibility: String,
    #[serde(default)]
    pub(crate) location_name: String,
    #[serde(default)]
    pub(crate) address_line1: String,
    #[serde(default)]
    pub(crate) address_line2: String,
    #[serde(default)]
    pub(crate) city: String,
    #[serde(default)]
    pub(crate) state_province: String,
    #[serde(default)]
    pub(crate) postal_code: String,
    #[serde(default)]
    pub(crate) country: String,
    #[serde(default)]
    pub(crate) location_notes: String,
    #[serde(default = "default_address_visibility")]
    pub(crate) address_visibility: String,
    pub(crate) csrf_token: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct EventEditForm {
    pub(crate) title: String,
    pub(crate) description: String,
    pub(crate) start_time: String,
    #[serde(default)]
    pub(crate) end_time: String,
    pub(crate) visibility: String,
    pub(crate) csrf_token: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct RsvpForm {
    pub(crate) status: String,
    #[serde(default)]
    pub(crate) guest_name: String,
    #[serde(default)]
    pub(crate) arrival_time: String,
    #[serde(default)]
    pub(crate) leaving_time: String,
    #[serde(default)]
    pub(crate) guest_count: String,
    #[serde(default)]
    pub(crate) travel_buffer_minutes: String,
    #[serde(default)]
    pub(crate) notes: String,
    pub(crate) csrf_token: String,
}

#[derive(Debug, Clone)]
pub(crate) struct EventPageContext {
    pub location: Option<pod_db::EventLocationRecord>,
    pub rsvps: Vec<EventRsvpRecord>,
    pub user_rsvp: Option<EventRsvpRecord>,
    pub deck_declarations: Vec<EventDeckDeclarationWithDeck>,
    pub user_decks: Vec<pod_db::DeckRecord>,
    pub pods: Vec<PodWithSeats>,
    pub games: Vec<GameWithPlayers>,
    pub show_address: bool,
    pub can_edit: bool,
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

async fn event_page_context(
    pool: &PgPool,
    repo: &EventRepository<'_>,
    event: &EventWithRole,
    user_id: Option<uuid::Uuid>,
    guest_scope: bool,
) -> Result<EventPageContext, DbError> {
    let hosts = repo.list_hosts(event.id).await?;
    let rsvps = repo.list_rsvps(event.id).await?;
    let user_rsvp =
        user_id.and_then(|id| rsvps.iter().find(|rsvp| rsvp.user_id == Some(id)).cloned());
    let role = PlaygroupRole::try_from(event.member_role.as_str()).ok();
    let address_visibilities = hosts
        .iter()
        .filter_map(|host| AddressVisibility::try_from(host.address_visibility.as_str()).ok())
        .collect::<Vec<_>>();
    let viewer_is_host =
        user_id.is_some_and(|user_id| hosts.iter().any(|host| host.user_id == user_id));
    let viewer_rsvp = user_rsvp
        .as_ref()
        .and_then(|rsvp| RsvpStatus::try_from(rsvp.status.as_str()).ok());
    let show_address = can_show_event_address(
        &address_visibilities,
        viewer_is_host,
        role,
        viewer_rsvp,
        guest_scope,
    );
    let location = repo
        .get_location_for_event_scoped(event.id, show_address)
        .await?;
    if show_address
        && location
            .as_ref()
            .is_some_and(|location| location.address_line1.is_some())
    {
        AuditRepository::new(pool)
            .record_address_reveal(
                event.id,
                user_id,
                if guest_scope {
                    "guest"
                } else {
                    "authenticated"
                },
                "event_detail",
            )
            .await?;
    }

    Ok(EventPageContext {
        location,
        rsvps,
        user_rsvp,
        deck_declarations: Vec::new(),
        user_decks: Vec::new(),
        pods: Vec::new(),
        games: Vec::new(),
        show_address,
        can_edit: role.is_some_and(can_manage_event),
    })
}

async fn public_event_page_context(
    pool: &PgPool,
    repo: &EventRepository<'_>,
    event_id: uuid::Uuid,
    source: &str,
) -> Result<EventPageContext, DbError> {
    let hosts = repo.list_hosts(event_id).await?;
    let address_visibilities = hosts
        .iter()
        .filter_map(|host| AddressVisibility::try_from(host.address_visibility.as_str()).ok())
        .collect::<Vec<_>>();
    let show_address = can_show_event_address(&address_visibilities, false, None, None, true);
    let location = repo
        .get_location_for_event_scoped(event_id, show_address)
        .await?;
    if show_address
        && location
            .as_ref()
            .is_some_and(|location| location.address_line1.is_some())
    {
        AuditRepository::new(pool)
            .record_address_reveal(event_id, None, "public_or_guest", source)
            .await?;
    }

    Ok(EventPageContext {
        location,
        rsvps: Vec::new(),
        user_rsvp: None,
        deck_declarations: Vec::new(),
        user_decks: Vec::new(),
        pods: Vec::new(),
        games: Vec::new(),
        show_address,
        can_edit: false,
    })
}

async fn render_collection_detail_response(
    state: &AppState,
    pool: &PgPool,
    user_id: uuid::Uuid,
    collection_id: uuid::Uuid,
    error: Option<&str>,
    headers: &HeaderMap,
) -> Response {
    let repo = CollectionRepository::new(pool);
    let collection = match repo.get_collection_for_user(collection_id, user_id).await {
        Ok(Some(collection)) => collection,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get collection");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let cards = match repo
        .list_collection_cards_for_user(collection_id, user_id)
        .await
    {
        Ok(cards) => cards,
        Err(err) => {
            tracing::error!(err = %err, "list collection cards");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let decks = match DeckRepository::new(pool)
        .list_owned_active_for_user(user_id)
        .await
    {
        Ok(decks) => decks,
        Err(err) => {
            tracing::error!(err = %err, "list active decks for collection");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let suggestions = match repo
        .deck_suggestions_for_collection(collection_id, user_id, 5)
        .await
    {
        Ok(suggestions) => suggestions,
        Err(err) => {
            tracing::error!(err = %err, "list collection deck suggestions");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let csrf = ensure_csrf_cookie(headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_collection_detail(
            &collection,
            &cards,
            &decks,
            &suggestions,
            &csrf.token,
            error,
            collection.owner_user_id == user_id,
        ),
        csrf.set_cookie,
    )
}

async fn render_wishlist_detail_response(
    state: &AppState,
    pool: &PgPool,
    user_id: uuid::Uuid,
    wishlist_id: uuid::Uuid,
    error: Option<&str>,
    headers: &HeaderMap,
) -> Response {
    let repo = CollectionRepository::new(pool);
    let wishlist = match repo.get_wishlist_for_user(wishlist_id, user_id).await {
        Ok(Some(wishlist)) => wishlist,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get wishlist");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let cards = match repo
        .list_wishlist_cards_for_user(wishlist_id, user_id)
        .await
    {
        Ok(cards) => cards,
        Err(err) => {
            tracing::error!(err = %err, "list wishlist cards");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let collections = match repo.list_collections_for_user(user_id).await {
        Ok(collections) => collections,
        Err(err) => {
            tracing::error!(err = %err, "list collections for wishlist coverage");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let csrf = ensure_csrf_cookie(headers, &state.config);
    html_with_cookies(
        StatusCode::OK,
        ui::render_wishlist_detail(
            &wishlist,
            &cards,
            &collections,
            &csrf.token,
            error,
            wishlist.owner_user_id == user_id,
        ),
        csrf.set_cookie,
    )
}

fn parse_rsvp_input<'a>(
    event_id: uuid::Uuid,
    user_id: Option<uuid::Uuid>,
    guest_name: Option<&'a str>,
    form: &'a RsvpForm,
) -> Result<RsvpInput<'a>, ()> {
    let status = RsvpStatus::try_from(form.status.trim())?;
    let guest_count = parse_optional_i32(&form.guest_count)
        .unwrap_or(Some(0))
        .ok_or(())?;
    if guest_count < 0 {
        return Err(());
    }
    let travel_buffer_minutes = parse_optional_i32(&form.travel_buffer_minutes).ok_or(())?;
    if travel_buffer_minutes.is_some_and(|minutes| minutes < 0) {
        return Err(());
    }

    Ok(RsvpInput {
        event_id,
        user_id,
        guest_name,
        status: status.as_str(),
        arrival_time: parse_optional_datetime_local(&form.arrival_time),
        leaving_time: parse_optional_datetime_local(&form.leaving_time),
        guest_count,
        travel_buffer_minutes,
        notes: form.notes.trim(),
    })
}

fn default_address_visibility() -> String {
    AddressVisibility::Rsvps.as_str().to_owned()
}

fn parse_collection_form(
    playgroups: &[pod_db::PlaygroupWithRole],
    form: &CollectionForm,
) -> Result<ParsedCollectionForm, &'static str> {
    let name = form.name.trim();
    if name.is_empty() {
        return Err("Collection name is required.");
    }
    let visibility =
        CollectionVisibility::try_from(default_if_empty(form.visibility.trim(), "private"))
            .map_err(|()| "Choose a valid collection visibility.")?
            .as_str()
            .to_owned();
    let playgroup_id = optional_trimmed(&form.playgroup_id)
        .map(str::parse)
        .transpose()
        .map_err(|_| "Choose a valid playgroup for playgroup-visible collections.")?;
    if playgroup_id.is_some_and(|id| !playgroups.iter().any(|playgroup| playgroup.id == id)) {
        return Err("Choose a playgroup you belong to.");
    }
    if visibility == CollectionVisibility::Playgroup.as_str() && playgroup_id.is_none() {
        return Err("Playgroup-visible collections need a playgroup.");
    }

    Ok(ParsedCollectionForm {
        playgroup_id,
        name: name.to_owned(),
        visibility,
        notes: form.notes.trim().to_owned(),
    })
}

fn parse_collection_card_form(
    form: &CollectionCardForm,
) -> Result<ParsedCollectionCardForm, &'static str> {
    let card_name = form.card_name.trim();
    if card_name.is_empty() {
        return Err("Card name is required.");
    }
    let quantity = parse_optional_i32(&form.quantity)
        .unwrap_or(Some(1))
        .ok_or("Quantity must be a number.")?;
    if quantity <= 0 {
        return Err("Quantity must be positive.");
    }
    let condition = CardCondition::try_from(default_if_empty(form.condition.trim(), "unknown"))
        .map_err(|()| "Choose a valid card condition.")?
        .as_str()
        .to_owned();

    Ok(ParsedCollectionCardForm {
        card_name: card_name.to_owned(),
        set_code: optional_trimmed(&form.set_code).map(str::to_owned),
        collector_number: optional_trimmed(&form.collector_number).map(str::to_owned),
        quantity,
        foil: form.foil,
        condition,
        location: form.location.trim().to_owned(),
    })
}

fn parse_wishlist_form(
    playgroups: &[pod_db::PlaygroupWithRole],
    form: &WishlistForm,
) -> Result<ParsedWishlistForm, &'static str> {
    let name = form.name.trim();
    if name.is_empty() {
        return Err("Wishlist name is required.");
    }
    let visibility =
        CollectionVisibility::try_from(default_if_empty(form.visibility.trim(), "private"))
            .map_err(|()| "Choose a valid wishlist visibility.")?
            .as_str()
            .to_owned();
    let playgroup_id = optional_trimmed(&form.playgroup_id)
        .map(str::parse)
        .transpose()
        .map_err(|_| "Choose a valid playgroup for playgroup-visible wishlists.")?;
    if playgroup_id.is_some_and(|id| !playgroups.iter().any(|playgroup| playgroup.id == id)) {
        return Err("Choose a playgroup you belong to.");
    }
    if visibility == CollectionVisibility::Playgroup.as_str() && playgroup_id.is_none() {
        return Err("Playgroup-visible wishlists need a playgroup.");
    }

    Ok(ParsedWishlistForm {
        playgroup_id,
        name: name.to_owned(),
        visibility,
        notes: form.notes.trim().to_owned(),
    })
}

fn parse_wishlist_card_form(
    form: &WishlistCardForm,
) -> Result<ParsedWishlistCardForm, &'static str> {
    let card_name = form.card_name.trim();
    if card_name.is_empty() {
        return Err("Card name is required.");
    }
    let desired_quantity = parse_optional_i32(&form.desired_quantity)
        .unwrap_or(Some(1))
        .ok_or("Quantity must be a number.")?;
    if desired_quantity <= 0 {
        return Err("Quantity must be positive.");
    }
    let priority = WishlistPriority::try_from(default_if_empty(form.priority.trim(), "medium"))
        .map_err(|()| "Choose a valid wishlist priority.")?
        .as_str()
        .to_owned();

    Ok(ParsedWishlistCardForm {
        card_name: card_name.to_owned(),
        desired_quantity,
        priority,
        notes: form.notes.trim().to_owned(),
    })
}

fn parse_deck_form(
    playgroups: &[pod_db::PlaygroupWithRole],
    form: &DeckForm,
) -> Result<ParsedDeckForm, &'static str> {
    let name = form.name.trim();
    let commander = form.commander.trim();
    if name.is_empty() || commander.is_empty() {
        return Err("Deck name and commander are required.");
    }

    let visibility = DeckVisibility::try_from(default_if_empty(form.visibility.trim(), "private"))
        .map_err(|()| "Choose a valid deck visibility.")?
        .as_str()
        .to_owned();
    let status = DeckStatus::try_from(default_if_empty(form.status.trim(), "active"))
        .map_err(|()| "Choose a valid deck status.")?
        .as_str()
        .to_owned();
    let tutor_density = TutorDensity::try_from(default_if_empty(form.tutor_density.trim(), "none"))
        .map_err(|()| "Choose a valid tutor density.")?
        .as_str()
        .to_owned();
    let game_changers_count = parse_optional_i32(&form.game_changers_count)
        .unwrap_or(Some(0))
        .ok_or("Game Changers count must be a number.")?;
    if game_changers_count < 0 {
        return Err("Game Changers count cannot be negative.");
    }

    let playgroup_id = optional_trimmed(&form.playgroup_id)
        .map(str::parse)
        .transpose()
        .map_err(|_| "Choose a valid playgroup for playgroup-visible decks.")?;
    if playgroup_id.is_some_and(|id| !playgroups.iter().any(|playgroup| playgroup.id == id)) {
        return Err("Choose a playgroup you belong to.");
    }
    if visibility == DeckVisibility::Playgroup.as_str() && playgroup_id.is_none() {
        return Err("Playgroup-visible decks need a playgroup.");
    }

    Ok(ParsedDeckForm {
        playgroup_id,
        name: name.to_owned(),
        commander: commander.to_owned(),
        color_identity: normalize_color_identity(&form.color_identity),
        claimed_bracket: form.claimed_bracket.trim().to_owned(),
        archetype: form.archetype.trim().to_owned(),
        tags: normalize_tags(&form.tags),
        visibility,
        status,
        game_changers_count,
        has_infinite_combo: form.has_infinite_combo,
        has_fast_mana: form.has_fast_mana,
        tutor_density,
        has_extra_turns: form.has_extra_turns,
        has_mass_land_denial: form.has_mass_land_denial,
        salt_notes: form.salt_notes.trim().to_owned(),
        notes: form.notes.trim().to_owned(),
    })
}

fn parse_export_format(value: &str) -> Option<DecklistExportFormat> {
    match value {
        "plain-text" | "plain" | "txt" => Some(DecklistExportFormat::PlainText),
        "moxfield" => Some(DecklistExportFormat::Moxfield),
        "archidekt" => Some(DecklistExportFormat::Archidekt),
        _ => None,
    }
}

fn decklist_section_from_db(value: &str) -> DecklistSection {
    match value {
        "commander" => DecklistSection::Commander,
        "sideboard" => DecklistSection::Sideboard,
        "maybeboard" => DecklistSection::Maybeboard,
        _ => DecklistSection::Main,
    }
}

fn decklist_export_filename(deck_name: &str, format: DecklistExportFormat) -> String {
    text_export_filename(deck_name, format.slug())
}

fn text_export_filename(name: &str, suffix: &str) -> String {
    let mut slug = String::new();
    let mut last_was_dash = false;
    for character in name.chars().flat_map(char::to_lowercase) {
        if character.is_ascii_alphanumeric() {
            slug.push(character);
            last_was_dash = false;
        } else if !last_was_dash && !slug.is_empty() {
            slug.push('-');
            last_was_dash = true;
        }
    }
    while slug.ends_with('-') {
        slug.pop();
    }
    if slug.is_empty() {
        slug.push_str("export");
    }
    format!("{slug}-{suffix}.txt")
}

fn optional_trimmed(value: &str) -> Option<&str> {
    let value = value.trim();
    (!value.is_empty()).then_some(value)
}

fn default_if_empty<'a>(value: &'a str, fallback: &'a str) -> &'a str {
    if value.is_empty() { fallback } else { value }
}

fn parse_optional_i32(value: &str) -> Option<Option<i32>> {
    let value = value.trim();
    if value.is_empty() {
        Some(None)
    } else {
        value.parse::<i32>().ok().map(Some)
    }
}

fn parse_optional_f64(value: &str) -> Option<Option<f64>> {
    let value = value.trim();
    if value.is_empty() {
        Some(None)
    } else {
        value.parse::<f64>().ok().map(Some)
    }
}

fn parse_elimination_order(form: &GameLogForm) -> Result<Vec<uuid::Uuid>, ()> {
    [
        form.elimination_1_user_id.as_str(),
        form.elimination_2_user_id.as_str(),
        form.elimination_3_user_id.as_str(),
        form.elimination_4_user_id.as_str(),
        form.elimination_5_user_id.as_str(),
    ]
    .into_iter()
    .filter_map(optional_trimmed)
    .map(|value| value.parse::<uuid::Uuid>().map_err(|_| ()))
    .collect()
}

fn parse_optional_datetime_local(value: &str) -> Option<OffsetDateTime> {
    let value = value.trim();
    if value.is_empty() {
        None
    } else {
        parse_datetime_local(value)
    }
}

fn parse_datetime_local(value: &str) -> Option<OffsetDateTime> {
    let (date, time) = value.trim().split_once('T')?;
    let mut date_parts = date.split('-');
    let year = date_parts.next()?.parse::<i32>().ok()?;
    let month = Month::try_from(date_parts.next()?.parse::<u8>().ok()?).ok()?;
    let day = date_parts.next()?.parse::<u8>().ok()?;
    if date_parts.next().is_some() {
        return None;
    }

    let mut time_parts = time.split(':');
    let hour = time_parts.next()?.parse::<u8>().ok()?;
    let minute = time_parts.next()?.parse::<u8>().ok()?;
    if time_parts.next().is_some() {
        return None;
    }

    let date = Date::from_calendar_date(year, month, day).ok()?;
    let time = Time::from_hms(hour, minute, 0).ok()?;
    Some(PrimitiveDateTime::new(date, time).assume_offset(UtcOffset::UTC))
}

fn new_public_token() -> String {
    new_session_token().encoded
}

fn render_calendar(events: &[pod_db::CalendarEventRecord]) -> String {
    let mut calendar =
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Pod Tracker//Events//EN\r\nCALSCALE:GREGORIAN\r\n"
            .to_owned();
    for event in events {
        calendar.push_str("BEGIN:VEVENT\r\n");
        calendar.push_str(&format!(
            "UID:{}\r\n",
            ics_escape(&format!("{}@pod-tracker.app", event.id))
        ));
        calendar.push_str(&format!(
            "DTSTAMP:{}\r\n",
            ics_timestamp(OffsetDateTime::now_utc())
        ));
        calendar.push_str(&format!("DTSTART:{}\r\n", ics_timestamp(event.start_time)));
        if let Some(end_time) = event.end_time {
            calendar.push_str(&format!("DTEND:{}\r\n", ics_timestamp(end_time)));
        }
        calendar.push_str(&format!("SUMMARY:{}\r\n", ics_escape(&event.title)));
        if !event.description.is_empty() {
            calendar.push_str(&format!(
                "DESCRIPTION:{}\r\n",
                ics_escape(&event.description)
            ));
        }
        if let Some(location_name) = event.location_name.as_ref() {
            calendar.push_str(&format!("LOCATION:{}\r\n", ics_escape(location_name)));
        }
        calendar.push_str("END:VEVENT\r\n");
    }
    calendar.push_str("END:VCALENDAR\r\n");
    calendar
}

fn ics_timestamp(value: OffsetDateTime) -> String {
    let value = value.to_offset(UtcOffset::UTC);
    format!(
        "{:04}{:02}{:02}T{:02}{:02}{:02}Z",
        value.year(),
        u8::from(value.month()),
        value.day(),
        value.hour(),
        value.minute(),
        value.second()
    )
}

fn ics_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace(';', "\\;")
        .replace(',', "\\,")
        .replace("\r\n", "\\n")
        .replace('\n', "\\n")
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
    use axum::Router;
    use axum::body::{Body, to_bytes};
    use axum::http::header::{CONTENT_DISPOSITION, CONTENT_TYPE, LOCATION, SET_COOKIE};
    use axum::http::{HeaderMap, Request, StatusCode};
    use pod_core::config::AppConfig;
    use pod_core::playgroups::PlaygroupRole;
    use pod_db::{
        CreateDeckInput, DeckRepository, DecklistImportInput, EventRepository, IdentityRepository,
        MetaRepository, PlaygroupRepository, PodRepository, ScryfallImportInput,
        ScryfallRepository,
    };
    use serde_json::json;
    use tower::ServiceExt;

    use super::{
        AppState, RateLimitFamily, build_router, rate_limit_family, route_family_label,
        session_cookie,
    };

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

    fn test_state_with_static_dir(static_dir: &str) -> AppState {
        AppState::new(
            AppConfig {
                addr: "127.0.0.1:0".to_owned(),
                database_url: None,
                environment: "test".to_owned(),
                static_dir: static_dir.to_owned(),
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

    struct SignedInUser {
        csrf_token: String,
        cookie_header: String,
    }

    async fn sign_up(app: &Router, email: &str, display_name: &str) -> SignedInUser {
        let form = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/signup")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("signup form");
        let csrf_cookie = set_cookie_pair(form.headers(), "pod_tracker_csrf=");
        let csrf_token = cookie_value(&csrf_cookie).to_owned();
        let email = email.replace('@', "%40");
        let display_name = display_name.replace(' ', "+");
        let signup = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/signup")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", csrf_cookie.clone())
                    .body(Body::from(format!(
                        "email={email}&display_name={display_name}&password=correct-horse-battery&csrf_token={csrf_token}"
                    )))
                    .expect("request"),
            )
            .await
            .expect("signup");
        assert_eq!(signup.status(), StatusCode::SEE_OTHER);
        let session_cookie = set_cookie_pair(signup.headers(), "pod_tracker_session=");

        SignedInUser {
            csrf_token,
            cookie_header: format!("{csrf_cookie}; {session_cookie}"),
        }
    }

    fn redirected_event_id(response: &axum::response::Response) -> uuid::Uuid {
        response
            .headers()
            .get(LOCATION)
            .expect("event redirect")
            .to_str()
            .expect("location str")
            .trim_start_matches("/events/")
            .parse()
            .expect("event uuid")
    }

    fn redirected_deck_id(response: &axum::response::Response) -> uuid::Uuid {
        response
            .headers()
            .get(LOCATION)
            .expect("deck redirect")
            .to_str()
            .expect("location str")
            .trim_start_matches("/decks/")
            .parse()
            .expect("deck uuid")
    }

    fn redirected_collection_id(response: &axum::response::Response) -> uuid::Uuid {
        response
            .headers()
            .get(LOCATION)
            .expect("collection redirect")
            .to_str()
            .expect("location str")
            .trim_start_matches("/collections/")
            .parse()
            .expect("collection uuid")
    }

    fn redirected_wishlist_id(response: &axum::response::Response) -> uuid::Uuid {
        response
            .headers()
            .get(LOCATION)
            .expect("wishlist redirect")
            .to_str()
            .expect("location str")
            .trim_start_matches("/wishlists/")
            .parse()
            .expect("wishlist uuid")
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
    async fn observatory_renders_safe_sql_surface() {
        let app = build_router(test_state());

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/observatory")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::OK);
        let body = body_string(response).await;
        assert!(body.contains("SQL Observatory"));
        assert!(body.contains("core.event_rsvps"));
        assert!(body.contains("core.pod_seats"));
        assert!(body.contains("search.card_documents"));
        assert!(body.contains("mtg.card_printings"));
        assert!(body.contains("Bracket compatibility"));
        assert!(body.contains("Reminders and job claiming"));
        assert!(body.contains("Matchup history"));
        assert!(body.contains("Meta dashboard materialized views"));
        assert!(body.contains("Scrubbed fixture"));
        assert!(!body.contains("address_line1"));
        assert!(!body.contains("invite_token"));
        assert!(!body.contains("to_address"));
        assert!(!body.contains("pod_tracker_session"));
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn cards_route_searches_local_scryfall_index(pool: sqlx::PgPool) {
        let repo = ScryfallRepository::new(&pool);
        let metadata = json!({
            "type": "default_cards",
            "updated_at": "2026-05-18T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/e2ef41e3-5778-4bc2-af3f-78eca4dd9c23",
            "download_uri": "https://data.scryfall.io/default-cards/default-cards-20260518090927.json"
        });
        let import = repo
            .create_import(ScryfallImportInput {
                bulk_type: "default_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download_uri"),
                source_updated_at: time::OffsetDateTime::now_utc(),
                content_type: "application/json",
                content_encoding: Some("gzip"),
                size_bytes: Some(538_716_896),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");
        repo.upsert_card_from_scryfall_json(import.id, &storm_kiln_artist_card())
            .await
            .expect("import card");

        let app = build_router(test_state_with_db(pool));
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/cards?q=treasure&commander_legal=true&color_identity=R&type_line=Shaman&max_usd=2")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::OK);
        let body = body_string(response).await;
        assert!(body.contains("Storm-Kiln Artist"));
        assert!(body.contains("Scryfall local index"));
        assert!(!body.contains("invite_token"));
        assert!(!body.contains("address_line1"));
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn meta_route_renders_member_scoped_dashboard(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool.clone()));
        let owner = sign_up(&app, "meta-route-owner@example.test", "Meta Route Owner").await;

        let create_group = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Meta+Route+Crew&description=Dashboards&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create group");
        assert_eq!(create_group.status(), StatusCode::SEE_OTHER);

        MetaRepository::new(&pool)
            .refresh_dashboard_views()
            .await
            .expect("refresh views");

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/meta")
                    .header("cookie", owner.cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("meta response");

        assert_eq!(response.status(), StatusCode::OK);
        let body = body_string(response).await;
        assert!(body.contains("Meta Dashboard"));
        assert!(body.contains("Meta Route Crew"));
        assert!(body.contains("RSVP yes rate"));
        assert!(!body.contains("invite_token"));
        assert!(!body.contains("address_line1"));
        assert!(!body.contains("to_address"));
    }

    #[tokio::test]
    async fn static_css_asset_is_served() {
        let app = build_router(test_state_with_static_dir(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/assets"
        )));

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/static/app.css")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::OK);
        let body = body_string(response).await;
        assert!(body.contains(":root"));
    }

    #[tokio::test]
    async fn responses_include_security_headers() {
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
        let headers = response.headers();

        assert_eq!(
            headers.get("x-content-type-options").expect("header"),
            "nosniff"
        );
        assert_eq!(
            headers.get("referrer-policy").expect("header"),
            "strict-origin-when-cross-origin"
        );
        assert_eq!(headers.get("x-frame-options").expect("header"), "DENY");
        assert_eq!(
            headers.get("content-security-policy").expect("header"),
            "default-src 'self'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
        );
        assert_eq!(
            headers.get("permissions-policy").expect("header"),
            "camera=(), microphone=(), geolocation=()"
        );
    }

    #[tokio::test]
    async fn missing_routes_render_structured_error_pages() {
        let app = build_router(test_state());

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/missing-page")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        assert_eq!(
            response.headers().get(CONTENT_TYPE).expect("content type"),
            "text/html; charset=utf-8"
        );
        let body = body_string(response).await;
        assert!(body.contains("Page not found"));
        assert!(body.contains("The requested page is not available."));
    }

    #[tokio::test]
    async fn rate_limits_login_attempts_by_route_family() {
        let app = build_router(test_state());

        for attempt in 0..10 {
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri("/login")
                        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                        .header("x-forwarded-for", "198.51.100.10")
                        .body(Body::from(format!(
                            "email=player{attempt}%40example.test&password=nope&csrf_token="
                        )))
                        .expect("request"),
                )
                .await
                .expect("login attempt");
            assert_ne!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        }

        let limited = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/login")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("x-forwarded-for", "198.51.100.10")
                    .body(Body::from(
                        "email=blocked%40example.test&password=nope&csrf_token=",
                    ))
                    .expect("request"),
            )
            .await
            .expect("limited login");

        assert_eq!(limited.status(), StatusCode::TOO_MANY_REQUESTS);
        let body = body_string(limited).await;
        assert!(body.contains("Too many requests"));
    }

    #[test]
    fn rate_limit_classification_covers_hardening_route_families_without_tokens() {
        assert_eq!(
            rate_limit_family(&http::Method::POST, "/signup"),
            Some(RateLimitFamily::Signup)
        );
        assert_eq!(
            rate_limit_family(&http::Method::POST, "/login"),
            Some(RateLimitFamily::Login)
        );
        assert_eq!(
            rate_limit_family(&http::Method::POST, "/rsvp/private-token"),
            Some(RateLimitFamily::Rsvp)
        );
        assert_eq!(
            rate_limit_family(&http::Method::GET, "/e/private-token"),
            Some(RateLimitFamily::Invite)
        );
        assert_eq!(
            rate_limit_family(
                &http::Method::POST,
                "/decks/00000000-0000-7000-8000-000000000001/import"
            ),
            Some(RateLimitFamily::DeckImport)
        );
        assert_eq!(
            rate_limit_family(&http::Method::GET, "/cards"),
            Some(RateLimitFamily::Search)
        );
        assert_eq!(
            rate_limit_family(
                &http::Method::POST,
                "/events/00000000-0000-7000-8000-000000000001/pods/generate"
            ),
            Some(RateLimitFamily::Admin)
        );
    }

    #[test]
    fn request_span_route_family_labels_are_stable_without_tokens() {
        assert_eq!(
            route_family_label(&http::Method::GET, "/e/private-token"),
            "invite"
        );
        assert_eq!(
            route_family_label(&http::Method::POST, "/rsvp/private-token"),
            "rsvp"
        );
        assert_eq!(
            route_family_label(
                &http::Method::POST,
                "/events/00000000-0000-7000-8000-000000000001/pods/generate"
            ),
            "admin"
        );
        assert_eq!(
            route_family_label(
                &http::Method::GET,
                "/decks/00000000-0000-7000-8000-000000000001"
            ),
            "decks"
        );
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

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn state_changing_app_routes_reject_missing_csrf(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool));
        let signed_in = sign_up(&app, "csrf-owner@example.test", "Csrf Owner").await;

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", signed_in.cookie_header)
                    .body(Body::from(
                        "name=Blocked+Group&description=Missing+token&csrf_token=",
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

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn event_routes_enforce_rsvp_only_address_visibility(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool.clone()));
        let owner = sign_up(&app, "event-owner@example.test", "Owner").await;

        let create_playgroup = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Friday+Night+Commander&description=Weekly+pods&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create playgroup");
        assert_eq!(create_playgroup.status(), StatusCode::SEE_OTHER);

        let create_event = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups/friday-night-commander/events")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "title=Friday+Pods&description=Bring+decks&start_time=2026-06-01T19:00&end_time=&visibility=public_safe&location_name=Kitchen+Table&address_line1=123+Private+St&address_line2=&city=Durham&state_province=NC&postal_code=27701&country=US&location_notes=Private+gate+code&address_visibility=rsvps&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create event");
        assert_eq!(create_event.status(), StatusCode::SEE_OTHER);
        let event_id = redirected_event_id(&create_event);

        let edit_form = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/events/{event_id}/edit"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("edit form");
        assert_eq!(edit_form.status(), StatusCode::OK);
        let edit_body = body_string(edit_form).await;
        assert!(edit_body.contains("Friday Pods"));

        let update_event = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/events/{event_id}/edit"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "title=Updated+Pods&description=Bring+two+decks&start_time=2026-06-01T19:30&end_time=&visibility=public_safe&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("update event");
        assert_eq!(update_event.status(), StatusCode::SEE_OTHER);

        let owner_user = IdentityRepository::new(&pool)
            .find_user_by_email("event-owner@example.test")
            .await
            .expect("owner user")
            .expect("owner user");
        let updated = EventRepository::new(&pool)
            .get_for_user(event_id, owner_user.id)
            .await
            .expect("updated event")
            .expect("updated event");
        assert_eq!(updated.title, "Updated Pods");

        let invite_token = sqlx::query!(
            "select invite_token from core.events where id = $1",
            event_id
        )
        .fetch_one(&pool)
        .await
        .expect("event token")
        .invite_token
        .expect("invite token");

        let public_event = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/e/{invite_token}"))
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("public event");
        assert_eq!(public_event.status(), StatusCode::OK);
        let public_body = body_string(public_event).await;
        assert!(public_body.contains("Kitchen Table"));
        assert!(!public_body.contains("123 Private St"));
        assert!(!public_body.contains("Private gate code"));

        let member = sign_up(&app, "event-member@example.test", "Member").await;
        let member_user = IdentityRepository::new(&pool)
            .find_user_by_email("event-member@example.test")
            .await
            .expect("member user")
            .expect("member user");
        let playgroup = PlaygroupRepository::new(&pool)
            .get_by_slug_for_user("friday-night-commander", owner_user.id)
            .await
            .expect("playgroup")
            .expect("playgroup");
        PlaygroupRepository::new(&pool)
            .add_membership(playgroup.id, member_user.id, PlaygroupRole::Member, None)
            .await
            .expect("add member");

        let member_before_rsvp = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/events/{event_id}"))
                    .header("cookie", member.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("member event before rsvp");
        assert_eq!(member_before_rsvp.status(), StatusCode::OK);
        let member_before_body = body_string(member_before_rsvp).await;
        assert!(!member_before_body.contains("123 Private St"));
        assert!(!member_before_body.contains("Private gate code"));

        let save_rsvp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/events/{event_id}/rsvp"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", member.cookie_header.clone())
                    .body(Body::from(format!(
                        "status=maybe&arrival_time=2026-06-01T19:15&leaving_time=&guest_count=1&travel_buffer_minutes=15&notes=Bringing+a+guest&csrf_token={}",
                        member.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("save rsvp");
        assert_eq!(save_rsvp.status(), StatusCode::SEE_OTHER);

        let member_after_rsvp = app
            .oneshot(
                Request::builder()
                    .uri(format!("/events/{event_id}"))
                    .header("cookie", member.cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("member event after rsvp");
        assert_eq!(member_after_rsvp.status(), StatusCode::OK);
        let member_after_body = body_string(member_after_rsvp).await;
        assert!(member_after_body.contains("123 Private St"));
        assert!(member_after_body.contains("Private gate code"));
        let member_rsvp = EventRepository::new(&pool)
            .get_user_rsvp(event_id, member_user.id)
            .await
            .expect("member rsvp")
            .expect("member rsvp");
        assert_eq!(member_rsvp.status, "maybe");
        assert_eq!(member_rsvp.guest_count, 1);
        assert_eq!(member_rsvp.travel_buffer_minutes, Some(15));
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn guest_rsvp_and_calendar_feed_are_scoped(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool.clone()));
        let owner = sign_up(&app, "calendar-owner@example.test", "Owner").await;

        let create_playgroup = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Calendar+Crew&description=Calendar&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create playgroup");
        assert_eq!(create_playgroup.status(), StatusCode::SEE_OTHER);

        let create_event = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups/calendar-crew/events")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "title=Calendar+Pods&description=Do+not+leak+address&start_time=2026-06-02T18:30&end_time=&visibility=invite_only&location_name=Private+House&address_line1=456+Hidden+Ave&address_line2=&city=Raleigh&state_province=NC&postal_code=27601&country=US&location_notes=&address_visibility=members&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create event");
        assert_eq!(create_event.status(), StatusCode::SEE_OTHER);
        let event_id = redirected_event_id(&create_event);
        let invite_token = sqlx::query!(
            "select invite_token from core.events where id = $1",
            event_id
        )
        .fetch_one(&pool)
        .await
        .expect("event token")
        .invite_token
        .expect("invite token");

        let rsvp_form = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/rsvp/{invite_token}"))
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("guest rsvp form");
        assert_eq!(rsvp_form.status(), StatusCode::OK);
        let guest_csrf_cookie = set_cookie_pair(rsvp_form.headers(), "pod_tracker_csrf=");
        let guest_csrf_token = cookie_value(&guest_csrf_cookie).to_owned();
        let guest_body = body_string(rsvp_form).await;
        assert!(guest_body.contains("Private House"));
        assert!(!guest_body.contains("456 Hidden Ave"));

        let guest_rsvp = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/rsvp/{invite_token}"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", guest_csrf_cookie)
                    .body(Body::from(format!(
                        "guest_name=Guest+Player&status=waitlist&arrival_time=&leaving_time=&guest_count=0&travel_buffer_minutes=&notes=Maybe+late&csrf_token={guest_csrf_token}"
                    )))
                    .expect("request"),
            )
            .await
            .expect("guest rsvp");
        assert_eq!(guest_rsvp.status(), StatusCode::SEE_OTHER);

        let rsvps = EventRepository::new(&pool)
            .list_rsvps(event_id)
            .await
            .expect("rsvps");
        assert_eq!(rsvps.len(), 1);
        assert_eq!(rsvps[0].guest_name.as_deref(), Some("Guest Player"));
        assert_eq!(rsvps[0].status, "waitlist");

        let unauth_calendar = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/calendar.ics")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("unauth calendar");
        assert_eq!(unauth_calendar.status(), StatusCode::SEE_OTHER);
        assert_eq!(
            unauth_calendar.headers().get(LOCATION).expect("location"),
            "/login"
        );

        let calendar = app
            .oneshot(
                Request::builder()
                    .uri("/calendar.ics")
                    .header("cookie", owner.cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("calendar");
        assert_eq!(calendar.status(), StatusCode::OK);
        let calendar_body = body_string(calendar).await;
        assert!(calendar_body.contains("BEGIN:VCALENDAR"));
        assert!(calendar_body.contains("SUMMARY:Calendar Pods"));
        assert!(calendar_body.contains("LOCATION:Private House"));
        assert!(!calendar_body.contains("456 Hidden Ave"));
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn deck_registry_search_and_event_declarations_are_scoped(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool.clone()));
        let owner = sign_up(&app, "deck-route-owner@example.test", "Owner").await;

        let create_playgroup = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Deck+Route+Crew&description=Decks&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create playgroup");
        assert_eq!(create_playgroup.status(), StatusCode::SEE_OTHER);

        let playgroup = PlaygroupRepository::new(&pool)
            .get_by_slug_for_user(
                "deck-route-crew",
                IdentityRepository::new(&pool)
                    .find_user_by_email("deck-route-owner@example.test")
                    .await
                    .expect("owner user")
                    .expect("owner user")
                    .id,
            )
            .await
            .expect("playgroup")
            .expect("playgroup");

        let create_deck = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/decks")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Atraxa+Counters&commander=Atraxa%2C+Praetors%27+Voice&color_identity=WUBG&claimed_bracket=3&archetype=Counters&tags=counters%2Cmidrange&visibility=private&playgroup_id={}&status=active&game_changers_count=1&has_fast_mana=true&tutor_density=medium&salt_notes=Fast+mana&notes=Main+deck&csrf_token={}",
                        playgroup.id,
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create deck");
        assert_eq!(create_deck.status(), StatusCode::SEE_OTHER);
        let deck_id = redirected_deck_id(&create_deck);

        let search = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/decks?q=midrange")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("deck search");
        assert_eq!(search.status(), StatusCode::OK);
        let search_body = body_string(search).await;
        assert!(search_body.contains("Atraxa Counters"));

        let outsider = sign_up(&app, "deck-route-outsider@example.test", "Outsider").await;
        let outsider_detail = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/decks/{deck_id}"))
                    .header("cookie", outsider.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("outsider deck detail");
        assert_eq!(outsider_detail.status(), StatusCode::NOT_FOUND);

        let scryfall = ScryfallRepository::new(&pool);
        let metadata = json!({
            "type": "default_cards",
            "updated_at": "2026-05-18T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/e2ef41e3-5778-4bc2-af3f-78eca4dd9c23",
            "download_uri": "https://data.scryfall.io/default-cards/default-cards-20260518090927.json"
        });
        let import = scryfall
            .create_import(ScryfallImportInput {
                bulk_type: "default_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download_uri"),
                source_updated_at: time::OffsetDateTime::now_utc(),
                content_type: "application/json",
                content_encoding: Some("gzip"),
                size_bytes: Some(538_716_896),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");
        scryfall
            .upsert_card_from_scryfall_json(
                import.id,
                &card_json(
                    "00000000-0000-7000-8000-000000000201",
                    "10000000-0000-7000-8000-000000000201",
                    "Atraxa, Praetors' Voice",
                    &["W", "U", "B", "G"],
                    "Legendary Creature - Phyrexian Angel Horror",
                    false,
                ),
            )
            .await
            .expect("import atraxa");
        scryfall
            .upsert_card_from_scryfall_json(
                import.id,
                &card_json(
                    "00000000-0000-7000-8000-000000000202",
                    "10000000-0000-7000-8000-000000000202",
                    "Sol Ring",
                    &[],
                    "Artifact",
                    true,
                ),
            )
            .await
            .expect("import sol ring");

        let outsider_import = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/decks/{deck_id}/import"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", outsider.cookie_header.clone())
                    .body(Body::from(format!(
                        "decklist=Commander%0A1+Atraxa%2C+Praetors%27+Voice&csrf_token={}",
                        outsider.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("outsider import");
        assert_eq!(outsider_import.status(), StatusCode::NOT_FOUND);

        let import_decklist = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/decks/{deck_id}/import"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "decklist=Commander%0A1+Atraxa%2C+Praetors%27+Voice%0ADeck%0A1+Sol+Ring%0A1+Missing+Card&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("import decklist");
        assert_eq!(import_decklist.status(), StatusCode::SEE_OTHER);

        let imported_detail = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/decks/{deck_id}"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("imported deck detail");
        assert_eq!(imported_detail.status(), StatusCode::OK);
        let imported_detail_body = body_string(imported_detail).await;
        assert!(imported_detail_body.contains("Bracket check"));
        assert!(imported_detail_body.contains("Similar decks"));
        assert!(imported_detail_body.contains("1 Game Changer"));
        assert!(imported_detail_body.contains("1 decklist line(s) did not match"));
        assert!(imported_detail_body.contains("Plain text"));
        assert!(imported_detail_body.contains("Moxfield"));
        assert!(imported_detail_body.contains("Archidekt"));

        let outsider_export = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/decks/{deck_id}/export/plain-text"))
                    .header("cookie", outsider.cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("outsider export");
        assert_eq!(outsider_export.status(), StatusCode::NOT_FOUND);

        let plain_export = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/decks/{deck_id}/export/plain-text"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("plain export");
        assert_eq!(plain_export.status(), StatusCode::OK);
        assert_eq!(
            plain_export
                .headers()
                .get(CONTENT_TYPE)
                .expect("content type"),
            "text/plain; charset=utf-8"
        );
        assert!(
            plain_export
                .headers()
                .get(CONTENT_DISPOSITION)
                .expect("content disposition")
                .to_str()
                .expect("content disposition str")
                .contains("atraxa-counters-plain-text.txt")
        );
        let plain_body = body_string(plain_export).await;
        assert!(plain_body.contains("Commander\n1 Atraxa, Praetors' Voice"));
        assert!(plain_body.contains("Deck\n1 Sol Ring"));
        assert!(plain_body.contains("1 Missing Card"));

        let moxfield_export = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/decks/{deck_id}/export/moxfield"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("moxfield export");
        assert_eq!(moxfield_export.status(), StatusCode::OK);
        let moxfield_body = body_string(moxfield_export).await;
        assert!(moxfield_body.contains("COMMANDER:\n1 Atraxa, Praetors' Voice"));
        assert!(moxfield_body.contains("MAINBOARD:\n1 Sol Ring"));

        let archidekt_export = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/decks/{deck_id}/export/archidekt"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("archidekt export");
        assert_eq!(archidekt_export.status(), StatusCode::OK);
        let archidekt_body = body_string(archidekt_export).await;
        assert!(archidekt_body.contains("1x Atraxa, Praetors' Voice `Commander`"));
        assert!(archidekt_body.contains("1x Sol Ring `Mainboard`"));

        let bad_export = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/decks/{deck_id}/export/csv"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("bad export");
        assert_eq!(bad_export.status(), StatusCode::NOT_FOUND);

        let create_event = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups/deck-route-crew/events")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "title=Deck+Night&description=Declare+decks&start_time=2026-06-03T19:00&end_time=&visibility=members&location_name=&address_line1=&address_line2=&city=&state_province=&postal_code=&country=&location_notes=&address_visibility=hidden&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create event");
        assert_eq!(create_event.status(), StatusCode::SEE_OTHER);
        let event_id = redirected_event_id(&create_event);

        let declare = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/events/{event_id}/decks"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "deck_id={deck_id}&preference=1&testing_notes=Testing+counter+package&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("declare deck");
        assert_eq!(declare.status(), StatusCode::SEE_OTHER);

        let event = app
            .oneshot(
                Request::builder()
                    .uri(format!("/events/{event_id}"))
                    .header("cookie", owner.cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("event detail");
        assert_eq!(event.status(), StatusCode::OK);
        let event_body = body_string(event).await;
        assert!(event_body.contains("Atraxa Counters"));
        assert!(event_body.contains("Testing counter package"));
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn pod_routes_generate_publish_and_enforce_permissions(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool.clone()));
        let owner = sign_up(&app, "pod-route-owner@example.test", "Owner").await;
        let member = sign_up(&app, "pod-route-member@example.test", "Member").await;

        let create_playgroup = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Pod+Route+Crew&description=Pods&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create playgroup");
        assert_eq!(create_playgroup.status(), StatusCode::SEE_OTHER);

        let identity = IdentityRepository::new(&pool);
        let owner_user = identity
            .find_user_by_email("pod-route-owner@example.test")
            .await
            .expect("owner user")
            .expect("owner user");
        let member_user = identity
            .find_user_by_email("pod-route-member@example.test")
            .await
            .expect("member user")
            .expect("member user");
        let playgroup = PlaygroupRepository::new(&pool)
            .get_by_slug_for_user("pod-route-crew", owner_user.id)
            .await
            .expect("playgroup")
            .expect("playgroup");
        PlaygroupRepository::new(&pool)
            .add_membership(playgroup.id, member_user.id, PlaygroupRole::Member, None)
            .await
            .expect("member membership");

        let create_event = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/playgroups/pod-route-crew/events")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "title=Pod+Night&description=Generate+pods&start_time=2026-06-05T19:00&end_time=&visibility=members&location_name=&address_line1=&address_line2=&city=&state_province=&postal_code=&country=&location_notes=&address_visibility=hidden&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create event");
        assert_eq!(create_event.status(), StatusCode::SEE_OTHER);
        let event_id = redirected_event_id(&create_event);

        for signed_in in [&owner, &member] {
            let rsvp = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri(format!("/events/{event_id}/rsvp"))
                        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                        .header("cookie", signed_in.cookie_header.clone())
                        .body(Body::from(format!(
                            "status=yes&arrival_time=&leaving_time=&guest_count=0&travel_buffer_minutes=&notes=&csrf_token={}",
                            signed_in.csrf_token
                        )))
                        .expect("request"),
                )
                .await
                .expect("rsvp");
            assert_eq!(rsvp.status(), StatusCode::SEE_OTHER);
        }

        let member_generate = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/events/{event_id}/pods/generate"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", member.cookie_header.clone())
                    .body(Body::from(format!("csrf_token={}", member.csrf_token)))
                    .expect("request"),
            )
            .await
            .expect("member generate");
        assert_eq!(member_generate.status(), StatusCode::FORBIDDEN);

        let owner_generate = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/events/{event_id}/pods/generate"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!("csrf_token={}", owner.csrf_token)))
                    .expect("request"),
            )
            .await
            .expect("owner generate");
        assert_eq!(owner_generate.status(), StatusCode::SEE_OTHER);

        let pods = PodRepository::new(&pool)
            .list_for_event(event_id)
            .await
            .expect("pods");
        assert_eq!(pods.len(), 1);
        assert_eq!(pods[0].seats.len(), 2);

        let owner_pods = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/events/{event_id}/pods"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("owner pods");
        assert_eq!(owner_pods.status(), StatusCode::OK);
        let owner_pods_body = body_string(owner_pods).await;
        assert!(owner_pods_body.contains("Pod 1"));
        assert!(owner_pods_body.contains("Generate"));

        let member_lock = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/pods/{}/lock", pods[0].pod.id))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", member.cookie_header.clone())
                    .body(Body::from(format!("csrf_token={}", member.csrf_token)))
                    .expect("request"),
            )
            .await
            .expect("member lock");
        assert_eq!(member_lock.status(), StatusCode::FORBIDDEN);

        let owner_lock = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/pods/{}/lock", pods[0].pod.id))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!("csrf_token={}", owner.csrf_token)))
                    .expect("request"),
            )
            .await
            .expect("owner lock");
        assert_eq!(owner_lock.status(), StatusCode::SEE_OTHER);

        let owner_publish = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/events/{event_id}/pods/publish"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!("csrf_token={}", owner.csrf_token)))
                    .expect("request"),
            )
            .await
            .expect("owner publish");
        assert_eq!(owner_publish.status(), StatusCode::SEE_OTHER);

        let active = PodRepository::new(&pool)
            .list_for_event(event_id)
            .await
            .expect("active pods");
        assert_eq!(active[0].pod.state, "active");

        let member_log = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/events/{event_id}/games"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", member.cookie_header.clone())
                    .body(Body::from(format!(
                        "pod_id={}&result_type=normal_win&winner_user_id={}&turn_count=7&duration_minutes=45&first_player_user_id={}&tags=midrange&notes=Member+attempt&csrf_token={}",
                        active[0].pod.id,
                        member_user.id,
                        owner_user.id,
                        member.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("member log");
        assert_eq!(member_log.status(), StatusCode::FORBIDDEN);

        let owner_log = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/events/{event_id}/games"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "pod_id={}&result_type=normal_win&winner_user_id={}&turn_count=7&duration_minutes=45&first_player_user_id={}&elimination_1_user_id={}&tags=midrange%2Clong+game&notes=Clean+combat+finish&complete_event=true&csrf_token={}",
                        active[0].pod.id,
                        owner_user.id,
                        member_user.id,
                        member_user.id,
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("owner log");
        assert_eq!(owner_log.status(), StatusCode::SEE_OTHER);

        let game_count = sqlx::query_scalar!(
            "select count(*)::int from core.games where event_id = $1",
            event_id
        )
        .fetch_one(&pool)
        .await
        .expect("game count")
        .unwrap_or(0);
        assert_eq!(game_count, 1);
        let matchup_count = sqlx::query_scalar!(
            "select count(*)::int from meta.matchup_history where event_id = $1",
            event_id
        )
        .fetch_one(&pool)
        .await
        .expect("matchup count")
        .unwrap_or(0);
        assert_eq!(matchup_count, 1);
        let completed_at = sqlx::query_scalar!(
            "select completed_at from core.events where id = $1",
            event_id
        )
        .fetch_one(&pool)
        .await
        .expect("completed");
        assert!(completed_at.is_some());
        let elimination_order = sqlx::query_scalar!(
            r#"
            select elimination_order
            from core.game_players
            where user_id = $1
            "#,
            member_user.id
        )
        .fetch_one(&pool)
        .await
        .expect("elimination order");
        assert_eq!(elimination_order, Some(1));

        let event_after_game = app
            .oneshot(
                Request::builder()
                    .uri(format!("/events/{event_id}"))
                    .header("cookie", owner.cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("event after game");
        assert_eq!(event_after_game.status(), StatusCode::OK);
        let event_after_game_body = body_string(event_after_game).await;
        assert!(event_after_game_body.contains("Game history"));
        assert!(event_after_game_body.contains("Clean combat finish"));
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn collection_routes_track_cards_missing_lists_and_scope_access(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool.clone()));
        let owner = sign_up(&app, "collection-route-owner@example.test", "Owner").await;
        let outsider = sign_up(&app, "collection-route-outsider@example.test", "Outsider").await;

        let scryfall = ScryfallRepository::new(&pool);
        let metadata = json!({
            "type": "default_cards",
            "updated_at": "2026-05-18T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/collection-route",
            "download_uri": "https://data.scryfall.io/default-cards/collection-route.json"
        });
        let import = scryfall
            .create_import(ScryfallImportInput {
                bulk_type: "default_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download uri"),
                source_updated_at: time::OffsetDateTime::now_utc(),
                content_type: "application/json",
                content_encoding: None,
                size_bytes: Some(4096),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");
        for card in [
            card_json(
                "00000000-0000-7200-8000-000000000001",
                "10000000-0000-7200-8000-000000000001",
                "Atraxa, Praetors' Voice",
                &["W", "U", "B", "G"],
                "Legendary Creature - Phyrexian Angel Horror",
                false,
            ),
            card_json(
                "00000000-0000-7200-8000-000000000002",
                "10000000-0000-7200-8000-000000000002",
                "Sol Ring",
                &[],
                "Artifact",
                false,
            ),
            card_json(
                "00000000-0000-7200-8000-000000000003",
                "10000000-0000-7200-8000-000000000003",
                "Counterspell",
                &["U"],
                "Instant",
                false,
            ),
        ] {
            scryfall
                .upsert_card_from_scryfall_json(import.id, &card)
                .await
                .expect("upsert card");
        }

        let create_collection = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/collections")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Route+Binder&visibility=private&playgroup_id=&notes=Blue+binder&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create collection");
        assert_eq!(create_collection.status(), StatusCode::SEE_OTHER);
        let collection_id = redirected_collection_id(&create_collection);

        let outsider_detail = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/collections/{collection_id}"))
                    .header("cookie", outsider.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("outsider collection detail");
        assert_eq!(outsider_detail.status(), StatusCode::NOT_FOUND);

        let add_card = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/collections/{collection_id}/cards"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "card_name=Sol+Ring&set_code=&collector_number=&quantity=1&foil=true&condition=near_mint&location=Blue+binder&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("add card");
        assert_eq!(add_card.status(), StatusCode::SEE_OTHER);

        let detail = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/collections/{collection_id}"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("collection detail");
        assert_eq!(detail.status(), StatusCode::OK);
        let detail_body = body_string(detail).await;
        assert!(detail_body.contains("Sol Ring"));
        assert!(detail_body.contains("Blue binder"));
        assert!(detail_body.contains("Deck gaps"));

        let owner_user = IdentityRepository::new(&pool)
            .find_user_by_email("collection-route-owner@example.test")
            .await
            .expect("owner")
            .expect("owner");
        let tags = Vec::new();
        let deck = DeckRepository::new(&pool)
            .create_deck(CreateDeckInput {
                owner_user_id: owner_user.id,
                playgroup_id: None,
                name: "Collection Route Deck",
                commander: "Atraxa, Praetors' Voice",
                color_identity: "WUBG",
                claimed_bracket: "3",
                archetype: "Midrange",
                tags: &tags,
                visibility: "private",
                status: "active",
                game_changers_count: 0,
                has_infinite_combo: false,
                has_fast_mana: false,
                tutor_density: "none",
                has_extra_turns: false,
                has_mass_land_denial: false,
                salt_notes: "",
                notes: "",
            })
            .await
            .expect("deck");
        DeckRepository::new(&pool)
            .import_plain_text_decklist(DecklistImportInput {
                deck_id: deck.id,
                owner_user_id: owner_user.id,
                source_text:
                    "Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n2 Sol Ring\n1 Counterspell\n",
            })
            .await
            .expect("import")
            .expect("summary");

        let detail_with_suggestions = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/collections/{collection_id}"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("collection detail with suggestions");
        assert_eq!(detail_with_suggestions.status(), StatusCode::OK);
        let detail_with_suggestions_body = body_string(detail_with_suggestions).await;
        assert!(detail_with_suggestions_body.contains("Buildable decks"));
        assert!(detail_with_suggestions_body.contains("Collection Route Deck"));
        assert!(detail_with_suggestions_body.contains("25% owned"));

        let missing = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!(
                        "/collections/{collection_id}/decks/{}/missing",
                        deck.id
                    ))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("missing cards");
        assert_eq!(missing.status(), StatusCode::OK);
        let missing_body = body_string(missing).await;
        assert!(missing_body.contains("Atraxa"));
        assert!(missing_body.contains("Counterspell"));
        assert!(missing_body.contains("Sol Ring"));

        let proxy = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!(
                        "/collections/{collection_id}/decks/{}/proxy-list",
                        deck.id
                    ))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("proxy list");
        assert_eq!(proxy.status(), StatusCode::OK);
        assert_eq!(
            proxy.headers().get(CONTENT_TYPE).expect("content type"),
            "text/plain; charset=utf-8"
        );
        let proxy_body = body_string(proxy).await;
        assert!(proxy_body.contains("Commander\n1 Atraxa, Praetors' Voice"));
        assert!(proxy_body.contains("Deck\n1 Counterspell\n1 Sol Ring"));

        let outsider_proxy = app
            .oneshot(
                Request::builder()
                    .uri(format!(
                        "/collections/{collection_id}/decks/{}/proxy-list",
                        deck.id
                    ))
                    .header("cookie", outsider.cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("outsider proxy list");
        assert_eq!(outsider_proxy.status(), StatusCode::NOT_FOUND);
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn wishlist_routes_create_update_compare_and_scope_access(pool: sqlx::PgPool) {
        let app = build_router(test_state_with_db(pool.clone()));
        let owner = sign_up(&app, "wishlist-route-owner@example.test", "Owner").await;
        let outsider = sign_up(&app, "wishlist-route-outsider@example.test", "Outsider").await;

        let scryfall = ScryfallRepository::new(&pool);
        let metadata = json!({
            "type": "default_cards",
            "updated_at": "2026-05-18T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/wishlist-route",
            "download_uri": "https://data.scryfall.io/default-cards/wishlist-route.json"
        });
        let import = scryfall
            .create_import(ScryfallImportInput {
                bulk_type: "default_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download uri"),
                source_updated_at: time::OffsetDateTime::now_utc(),
                content_type: "application/json",
                content_encoding: None,
                size_bytes: Some(4096),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");
        for card in [
            card_json(
                "00000000-0000-7300-8000-000000000002",
                "10000000-0000-7300-8000-000000000002",
                "Sol Ring",
                &[],
                "Artifact",
                false,
            ),
            card_json(
                "00000000-0000-7300-8000-000000000003",
                "10000000-0000-7300-8000-000000000003",
                "Counterspell",
                &["U"],
                "Instant",
                false,
            ),
        ] {
            scryfall
                .upsert_card_from_scryfall_json(import.id, &card)
                .await
                .expect("upsert card");
        }

        let create_wishlist = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/wishlists")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Upgrade+Targets&visibility=private&playgroup_id=&notes=Trade+plans&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create wishlist");
        assert_eq!(create_wishlist.status(), StatusCode::SEE_OTHER);
        let wishlist_id = redirected_wishlist_id(&create_wishlist);

        let outsider_detail = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/wishlists/{wishlist_id}"))
                    .header("cookie", outsider.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("outsider wishlist detail");
        assert_eq!(outsider_detail.status(), StatusCode::NOT_FOUND);

        for body in [
            format!(
                "card_name=Counterspel&desired_quantity=2&priority=high&notes=Need+spares&csrf_token={}",
                owner.csrf_token
            ),
            format!(
                "card_name=Sol+Ring&desired_quantity=2&priority=medium&notes=Extra+copy&csrf_token={}",
                owner.csrf_token
            ),
            format!(
                "card_name=Counterspell&desired_quantity=3&priority=high&notes=Updated+target&csrf_token={}",
                owner.csrf_token
            ),
        ] {
            let add_card = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri(format!("/wishlists/{wishlist_id}/cards"))
                        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                        .header("cookie", owner.cookie_header.clone())
                        .body(Body::from(body))
                        .expect("request"),
                )
                .await
                .expect("add wishlist card");
            assert_eq!(add_card.status(), StatusCode::SEE_OTHER);
        }

        let detail = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/wishlists/{wishlist_id}"))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("wishlist detail");
        assert_eq!(detail.status(), StatusCode::OK);
        let detail_body = body_string(detail).await;
        assert!(detail_body.contains("Counterspell"));
        assert!(detail_body.contains("Updated target"));
        assert!(detail_body.contains("Collection coverage"));

        let create_collection = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/collections")
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "name=Wishlist+Binder&visibility=private&playgroup_id=&notes=Owned+cards&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("create collection");
        assert_eq!(create_collection.status(), StatusCode::SEE_OTHER);
        let collection_id = redirected_collection_id(&create_collection);

        let add_owned = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/collections/{collection_id}/cards"))
                    .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::from(format!(
                        "card_name=Sol+Ring&set_code=&collector_number=&quantity=1&foil=false&condition=unknown&location=&csrf_token={}",
                        owner.csrf_token
                    )))
                    .expect("request"),
            )
            .await
            .expect("add owned card");
        assert_eq!(add_owned.status(), StatusCode::SEE_OTHER);

        let needed = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!(
                        "/wishlists/{wishlist_id}/collections/{collection_id}/missing"
                    ))
                    .header("cookie", owner.cookie_header.clone())
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("wishlist needed");
        assert_eq!(needed.status(), StatusCode::OK);
        let needed_body = body_string(needed).await;
        assert!(needed_body.contains("Counterspell"));
        assert!(needed_body.contains("Sol Ring"));
        assert!(needed_body.contains("Needed"));

        let outsider_needed = app
            .oneshot(
                Request::builder()
                    .uri(format!(
                        "/wishlists/{wishlist_id}/collections/{collection_id}/missing"
                    ))
                    .header("cookie", outsider.cookie_header)
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("outsider wishlist needed");
        assert_eq!(outsider_needed.status(), StatusCode::NOT_FOUND);
    }

    fn storm_kiln_artist_card() -> serde_json::Value {
        json!({
            "id": "00000000-0000-7000-8000-000000000012",
            "oracle_id": "10000000-0000-7000-8000-000000000012",
            "name": "Storm-Kiln Artist",
            "lang": "en",
            "released_at": "2021-04-23",
            "layout": "normal",
            "mana_cost": "{3}{R}",
            "cmc": 4.0,
            "type_line": "Creature - Dwarf Shaman",
            "oracle_text": "Magecraft - Whenever you cast or copy an instant or sorcery spell, create a Treasure token.",
            "colors": ["R"],
            "color_identity": ["R"],
            "keywords": ["Magecraft"],
            "legalities": {
                "commander": "legal",
                "modern": "legal",
                "standard": "not_legal"
            },
            "reserved": false,
            "game_changer": false,
            "edhrec_rank": 135,
            "set": "stx",
            "collector_number": "115",
            "rarity": "uncommon",
            "artist": "Manuel Castanon",
            "prices": {
                "usd": "0.25",
                "eur": "0.12",
                "tix": "0.03"
            }
        })
    }

    fn card_json(
        scryfall_id: &str,
        oracle_id: &str,
        name: &str,
        color_identity: &[&str],
        type_line: &str,
        game_changer: bool,
    ) -> serde_json::Value {
        json!({
            "id": scryfall_id,
            "oracle_id": oracle_id,
            "name": name,
            "lang": "en",
            "released_at": "2026-01-01",
            "layout": "normal",
            "mana_cost": "",
            "cmc": 1.0,
            "type_line": type_line,
            "oracle_text": "Fixture card.",
            "colors": color_identity,
            "color_identity": color_identity,
            "keywords": [],
            "legalities": {
                "commander": "legal"
            },
            "reserved": false,
            "game_changer": game_changer,
            "edhrec_rank": 100,
            "set": "tst",
            "collector_number": "1",
            "rarity": "rare",
            "artist": "Fixture Artist",
            "prices": {
                "usd": "1.00"
            }
        })
    }
}
