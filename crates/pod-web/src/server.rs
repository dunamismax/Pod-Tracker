use axum::body::Body;
use axum::extract::State;
use axum::http::header::{CONTENT_DISPOSITION, CONTENT_TYPE, COOKIE, SET_COOKIE, USER_AGENT};
use axum::http::{HeaderMap, HeaderName, HeaderValue, Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{Html, IntoResponse, Redirect, Response};
use axum::routing::{get, post};
use axum::{Form, Json, Router};
use pod_core::auth::{
    AuthError, SESSION_COOKIE_NAME, hash_password, hash_session_token, new_session_token,
    verify_password,
};
use pod_core::config::AppConfig;
use pod_core::events::{
    AddressVisibility, EventVisibility, RsvpStatus, can_manage_event, can_show_event_address,
};
use pod_core::health::{HealthResponse, ReadinessFailure};
use pod_core::playgroups::{PlaygroupRole, slugify};
use pod_db::{
    CreateEventInput, DbError, EventLocationInput, EventRepository, EventRsvpRecord, EventWithRole,
    IdentityRepository, PlaygroupRepository, RsvpInput, UpdateEventInput, UserRecord,
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
        .route("/playgroups/{slug}/events/new", get(new_event_form))
        .route("/playgroups/{slug}/events", post(create_event))
        .route("/events", get(events))
        .route("/events/{id}", get(event_detail))
        .route("/events/{id}/edit", get(edit_event_form).post(update_event))
        .route("/events/{id}/rsvp", post(save_user_rsvp))
        .route("/e/{token}", get(public_event_detail))
        .route("/rsvp/{token}", get(guest_rsvp_form).post(save_guest_rsvp))
        .route("/calendar.ics", get(calendar_feed))
        .route("/observatory", get(observatory))
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .nest_service("/static", ServeDir::new(state.config.static_dir.clone()))
        .with_state(state)
        .layer(CompressionLayer::new())
        .layer(PropagateRequestIdLayer::new(request_id_header.clone()))
        .layer(SetRequestIdLayer::new(request_id_header, MakeRequestUuid))
        .layer(TraceLayer::new_for_http())
        .layer(middleware::from_fn(add_security_headers))
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

    let context = match event_page_context(&repo, &event, Some(user.id), false).await {
        Ok(context) => context,
        Err(err) => {
            tracing::error!(err = %err, "load event context");
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

async fn public_event_detail(
    State(state): State<AppState>,
    axum::extract::Path(token): axum::extract::Path<String>,
) -> Response {
    let Some(pool) = state.db.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let repo = EventRepository::new(pool);
    let event = match repo.get_by_token(token.trim()).await {
        Ok(Some(event)) if event.visibility == EventVisibility::PublicSafe.as_str() => event,
        Ok(_) => return StatusCode::NOT_FOUND.into_response(),
        Err(err) => {
            tracing::error!(err = %err, "get public event");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let context = match public_event_page_context(&repo, event.id).await {
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
    let context = match public_event_page_context(&repo, event.id).await {
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
        let context = match public_event_page_context(&repo, event.id).await {
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
    repo: &EventRepository<'_>,
    event: &EventWithRole,
    user_id: Option<uuid::Uuid>,
    guest_scope: bool,
) -> Result<EventPageContext, DbError> {
    let location = repo.get_location_for_event(event.id).await?;
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

    Ok(EventPageContext {
        location,
        rsvps,
        user_rsvp,
        show_address,
        can_edit: role.is_some_and(can_manage_event),
    })
}

async fn public_event_page_context(
    repo: &EventRepository<'_>,
    event_id: uuid::Uuid,
) -> Result<EventPageContext, DbError> {
    let location = repo.get_location_for_event(event_id).await?;
    let hosts = repo.list_hosts(event_id).await?;
    let address_visibilities = hosts
        .iter()
        .filter_map(|host| AddressVisibility::try_from(host.address_visibility.as_str()).ok())
        .collect::<Vec<_>>();
    let show_address = can_show_event_address(&address_visibilities, false, None, None, true);

    Ok(EventPageContext {
        location,
        rsvps: Vec::new(),
        user_rsvp: None,
        show_address,
        can_edit: false,
    })
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

fn optional_trimmed(value: &str) -> Option<&str> {
    let value = value.trim();
    (!value.is_empty()).then_some(value)
}

fn parse_optional_i32(value: &str) -> Option<Option<i32>> {
    let value = value.trim();
    if value.is_empty() {
        Some(None)
    } else {
        value.parse::<i32>().ok().map(Some)
    }
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
    use axum::http::header::{CONTENT_TYPE, LOCATION, SET_COOKIE};
    use axum::http::{HeaderMap, Request, StatusCode};
    use pod_core::config::AppConfig;
    use pod_core::playgroups::PlaygroupRole;
    use pod_db::{EventRepository, IdentityRepository, PlaygroupRepository};
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
                        "title=Friday+Pods&description=Bring+decks&start_time=2026-06-01T19:00&end_time=&visibility=public_safe&location_name=Kitchen+Table&address_line1=123+Private+St&address_line2=&city=Durham&state_province=NC&postal_code=27701&country=US&location_notes=&address_visibility=rsvps&csrf_token={}",
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
}
