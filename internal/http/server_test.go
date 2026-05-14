package httpserver

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"regexp"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/dunamismax/pod-tracker/internal/auth"
	"github.com/dunamismax/pod-tracker/internal/config"
)

func TestHealthAndReadiness(t *testing.T) {
	server := newTestServer(t)

	for _, path := range []string{"/healthz", "/readyz"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()

		server.Handler().ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("%s returned status %d", path, rec.Code)
		}
		if rec.Header().Get("X-Request-ID") == "" {
			t.Fatalf("%s did not set a request id", path)
		}
	}
}

func TestHomePageRenders(t *testing.T) {
	server := newTestServer(t)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	server.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("home returned status %d", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, "Pod Tracker") {
		t.Fatalf("home page did not render product name")
	}
	if !strings.Contains(body, "/static/vendor/htmx-2.0.10.min.js") {
		t.Fatalf("home page did not include pinned htmx asset")
	}
}

func TestReadinessFailsWhenCheckFails(t *testing.T) {
	server := newTestServerWithOptions(t, WithReadinessCheck("database", func(_ context.Context) error {
		return errors.New("offline")
	}))
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	server.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("readyz returned status %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "not_ready") {
		t.Fatalf("readyz did not report not_ready")
	}
}

func TestSignupCreatesSecureSessionCookie(t *testing.T) {
	store := newFakeStore()
	server := newTestServerWithOptions(t, WithStore(store))
	csrfCookie, csrf := getCSRF(t, server, "/signup")

	form := url.Values{}
	form.Set("csrf_token", csrf)
	form.Set("email", "PLAYER@example.com")
	form.Set("display_name", "Player One")
	form.Set("password", "long-enough-password")
	req := httptest.NewRequest(http.MethodPost, "/signup", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.AddCookie(csrfCookie)
	rec := httptest.NewRecorder()

	server.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusSeeOther {
		t.Fatalf("signup returned status %d", rec.Code)
	}
	if rec.Header().Get("Location") != "/home" {
		t.Fatalf("signup redirected to %q", rec.Header().Get("Location"))
	}
	sessionCookie := findCookie(rec.Result().Cookies(), auth.SessionCookieName)
	if sessionCookie == nil {
		t.Fatalf("signup did not set a session cookie")
	}
	if !sessionCookie.HttpOnly {
		t.Fatalf("session cookie is not HttpOnly")
	}
	if sessionCookie.SameSite != http.SameSiteLaxMode {
		t.Fatalf("session cookie SameSite = %v", sessionCookie.SameSite)
	}
	if _, ok := store.usersByEmail["player@example.com"]; !ok {
		t.Fatalf("signup did not normalize and store email")
	}
}

func TestProtectedRoutesRedirectToLogin(t *testing.T) {
	server := newTestServer(t)
	req := httptest.NewRequest(http.MethodGet, "/settings", nil)
	rec := httptest.NewRecorder()

	server.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusSeeOther {
		t.Fatalf("settings returned status %d", rec.Code)
	}
	if rec.Header().Get("Location") != "/login" {
		t.Fatalf("settings redirected to %q", rec.Header().Get("Location"))
	}
}

func TestStateChangingRoutesRequireCSRF(t *testing.T) {
	server := newTestServer(t)
	req := httptest.NewRequest(http.MethodPost, "/logout", nil)
	rec := httptest.NewRecorder()

	server.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("logout without csrf returned status %d", rec.Code)
	}
}

func TestAuthenticatedUserCanCreateAndListPlaygroups(t *testing.T) {
	store := newFakeStore()
	server := newTestServerWithOptions(t, WithStore(store))
	csrfCookie, signupCSRF := getCSRF(t, server, "/signup")
	sessionCookie := signupForTest(t, server, csrfCookie, signupCSRF)

	req := httptest.NewRequest(http.MethodGet, "/playgroups", nil)
	req.AddCookie(csrfCookie)
	req.AddCookie(sessionCookie)
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("playgroups returned status %d", rec.Code)
	}
	playgroupCSRF := extractCSRF(t, rec.Body.String())

	form := url.Values{}
	form.Set("csrf_token", playgroupCSRF)
	form.Set("name", "Kitchen Table Crew")
	form.Set("description", "Wednesday commander nights")
	req = httptest.NewRequest(http.MethodPost, "/playgroups", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.AddCookie(csrfCookie)
	req.AddCookie(sessionCookie)
	rec = httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, req)
	if rec.Code != http.StatusSeeOther {
		t.Fatalf("create playgroup returned status %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/playgroups", nil)
	req.AddCookie(csrfCookie)
	req.AddCookie(sessionCookie)
	rec = httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, req)
	if !strings.Contains(rec.Body.String(), "Kitchen Table Crew") {
		t.Fatalf("created playgroup was not listed")
	}
	if !strings.Contains(rec.Body.String(), "owner") {
		t.Fatalf("created playgroup role was not listed")
	}
}

func newTestServer(t *testing.T) *Server {
	t.Helper()

	return newTestServerWithOptions(t)
}

func newTestServerWithOptions(t *testing.T, opts ...Option) *Server {
	t.Helper()

	server, err := New(config.Config{
		Addr:        ":0",
		Environment: "test",
		StaticDir:   "../../web/static",
		TemplateDir: "../../web/templates",
	}, slog.New(slog.NewTextHandler(io.Discard, nil)), opts...)
	if err != nil {
		t.Fatalf("new server: %v", err)
	}
	return server
}

func getCSRF(t *testing.T, server *Server, path string) (*http.Cookie, string) {
	t.Helper()

	req := httptest.NewRequest(http.MethodGet, path, nil)
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("%s returned status %d", path, rec.Code)
	}
	cookie := findCookie(rec.Result().Cookies(), csrfCookieName)
	if cookie == nil {
		t.Fatalf("%s did not set csrf cookie", path)
	}
	return cookie, extractCSRF(t, rec.Body.String())
}

func signupForTest(t *testing.T, server *Server, csrfCookie *http.Cookie, csrf string) *http.Cookie {
	t.Helper()

	form := url.Values{}
	form.Set("csrf_token", csrf)
	form.Set("email", "player@example.com")
	form.Set("display_name", "Player One")
	form.Set("password", "long-enough-password")
	req := httptest.NewRequest(http.MethodPost, "/signup", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.AddCookie(csrfCookie)
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, req)
	if rec.Code != http.StatusSeeOther {
		t.Fatalf("signup returned status %d", rec.Code)
	}
	cookie := findCookie(rec.Result().Cookies(), auth.SessionCookieName)
	if cookie == nil {
		t.Fatalf("signup did not set session cookie")
	}
	return cookie
}

func extractCSRF(t *testing.T, body string) string {
	t.Helper()

	match := regexp.MustCompile(`name="csrf_token" value="([^"]+)"`).FindStringSubmatch(body)
	if len(match) != 2 {
		t.Fatalf("csrf token not found in body")
	}
	return match[1]
}

func findCookie(cookies []*http.Cookie, name string) *http.Cookie {
	for _, cookie := range cookies {
		if cookie.Name == name {
			return cookie
		}
	}
	return nil
}

type fakeStore struct {
	nextID       byte
	usersByID    map[string]UserWithPassword
	usersByEmail map[string]UserWithPassword
	sessions     map[string]Session
	playgroups   []Playgroup
}

func newFakeStore() *fakeStore {
	return &fakeStore{
		usersByID:    map[string]UserWithPassword{},
		usersByEmail: map[string]UserWithPassword{},
		sessions:     map[string]Session{},
	}
}

func (s *fakeStore) CreateUser(_ context.Context, params CreateUserParams) (User, error) {
	if _, ok := s.usersByEmail[params.Email]; ok {
		return User{}, errors.New("duplicate user")
	}
	user := User{
		ID:          s.nextUUID(),
		Email:       params.Email,
		DisplayName: params.DisplayName,
	}
	withPassword := UserWithPassword{User: user, PasswordHash: params.PasswordHash}
	s.usersByID[uuidKey(user.ID)] = withPassword
	s.usersByEmail[user.Email] = withPassword
	return user, nil
}

func (s *fakeStore) GetUserByEmail(_ context.Context, email string) (UserWithPassword, error) {
	user, ok := s.usersByEmail[email]
	if !ok {
		return UserWithPassword{}, pgx.ErrNoRows
	}
	return user, nil
}

func (s *fakeStore) GetUserByID(_ context.Context, id pgtype.UUID) (User, error) {
	user, ok := s.usersByID[uuidKey(id)]
	if !ok {
		return User{}, pgx.ErrNoRows
	}
	return user.User, nil
}

func (s *fakeStore) CreateSession(_ context.Context, params CreateSessionParams) error {
	s.sessions[string(params.TokenHash)] = Session{UserID: params.UserID}
	return nil
}

func (s *fakeStore) GetSessionByTokenHash(_ context.Context, tokenHash []byte) (Session, error) {
	session, ok := s.sessions[string(tokenHash)]
	if !ok {
		return Session{}, pgx.ErrNoRows
	}
	return session, nil
}

func (s *fakeStore) RevokeSession(_ context.Context, tokenHash []byte) error {
	delete(s.sessions, string(tokenHash))
	return nil
}

func (s *fakeStore) ListPlaygroupsForUser(_ context.Context, _ pgtype.UUID) ([]Playgroup, error) {
	return append([]Playgroup(nil), s.playgroups...), nil
}

func (s *fakeStore) CreatePlaygroup(_ context.Context, params CreatePlaygroupParams) (Playgroup, error) {
	playgroup := Playgroup{
		ID:          s.nextUUID(),
		Name:        params.Name,
		Slug:        params.Slug,
		Description: params.Description,
		Role:        "owner",
	}
	s.playgroups = append(s.playgroups, playgroup)
	return playgroup, nil
}

func (s *fakeStore) GetPlaygroupBySlugAndUser(ctx context.Context, slug string, userID pgtype.UUID) (Playgroup, error) {
	return Playgroup{}, nil
}

func (s *fakeStore) CreateEvent(ctx context.Context, params CreateEventParams) (Event, error) {
	return Event{}, nil
}

func (s *fakeStore) GetEventByID(ctx context.Context, id pgtype.UUID) (Event, error) {
	return Event{}, nil
}

func (s *fakeStore) ListEventsForPlaygroup(ctx context.Context, playgroupID pgtype.UUID) ([]Event, error) {
	return nil, nil
}

func (s *fakeStore) UpdateEvent(ctx context.Context, params UpdateEventParams) (Event, error) {
	return Event{}, nil
}

func (s *fakeStore) nextUUID() pgtype.UUID {
	s.nextID++
	var bytes [16]byte
	bytes[15] = s.nextID
	return pgtype.UUID{Bytes: bytes, Valid: true}
}

func uuidKey(id pgtype.UUID) string {
	return string(id.Bytes[:])
}
