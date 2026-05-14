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
	"time"

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

func TestPublicEventPageHidesRSVPOnlyAddress(t *testing.T) {
	store := newFakeStore()
	server := newTestServerWithOptions(t, WithStore(store))
	event := store.seedEvent("public-token-for-test", "public_safe", "rsvps")

	req := httptest.NewRequest(http.MethodGet, "/e/"+event.InviteToken, nil)
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("public event returned status %d", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, "Kitchen Table") {
		t.Fatalf("public event did not show public location name")
	}
	if strings.Contains(body, "Hidden Address Sentinel") {
		t.Fatalf("public event exposed rsvp-scoped address")
	}
}

func TestMemberRSVPCanSeeRSVPOnlyAddress(t *testing.T) {
	store := newFakeStore()
	server := newTestServerWithOptions(t, WithStore(store))
	csrfCookie, csrf := getCSRF(t, server, "/signup")
	sessionCookie := signupForTest(t, server, csrfCookie, csrf)
	user := store.usersByEmail["player@example.com"].User
	event := store.seedEvent("member-token-for-test", "members", "rsvps")
	store.rsvps[uuidKey(event.ID)] = []EventRSVP{{
		ID:      store.nextUUID(),
		EventID: event.ID,
		UserID:  user.ID,
		Status:  "yes",
	}}

	req := httptest.NewRequest(http.MethodGet, "/events/"+uuidString(t, event.ID), nil)
	req.AddCookie(csrfCookie)
	req.AddCookie(sessionCookie)
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("event view returned status %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "Hidden Address Sentinel") {
		t.Fatalf("confirmed member rsvp did not see rsvp-scoped address")
	}
}

func TestGuestInviteRSVPCreatesGuestScopedRSVP(t *testing.T) {
	store := newFakeStore()
	server := newTestServerWithOptions(t, WithStore(store))
	event := store.seedEvent("invite-token-for-test", "invite_only", "hidden")
	csrfCookie, csrf := getCSRF(t, server, "/rsvp/"+event.InviteToken)

	form := url.Values{}
	form.Set("csrf_token", csrf)
	form.Set("guest_name", "Guest Player")
	form.Set("status", "maybe")
	req := httptest.NewRequest(http.MethodPost, "/rsvp/"+event.InviteToken, strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.AddCookie(csrfCookie)
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusSeeOther {
		t.Fatalf("guest rsvp returned status %d", rec.Code)
	}
	rsvps := store.rsvps[uuidKey(event.ID)]
	if len(rsvps) != 1 || rsvps[0].GuestName == nil || *rsvps[0].GuestName != "Guest Player" {
		t.Fatalf("guest rsvp was not stored with guest scope: %#v", rsvps)
	}
}

func TestAuthenticatedCalendarFeedIncludesEvents(t *testing.T) {
	store := newFakeStore()
	server := newTestServerWithOptions(t, WithStore(store))
	csrfCookie, csrf := getCSRF(t, server, "/signup")
	sessionCookie := signupForTest(t, server, csrfCookie, csrf)
	playgroup := Playgroup{ID: store.nextUUID(), Name: "Calendar Crew", Slug: "calendar-crew", Role: "member"}
	store.playgroups = append(store.playgroups, playgroup)
	event := store.seedEvent("calendar-token-for-test", "members", "members")
	event.PlaygroupID = playgroup.ID
	store.events[uuidKey(event.ID)] = event
	store.eventsByToken[event.InviteToken] = event

	req := httptest.NewRequest(http.MethodGet, "/calendar.ics", nil)
	req.AddCookie(csrfCookie)
	req.AddCookie(sessionCookie)
	rec := httptest.NewRecorder()
	server.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("calendar returned status %d", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, "BEGIN:VCALENDAR") || !strings.Contains(body, "SUMMARY:Commander Night") {
		t.Fatalf("calendar feed did not include event: %s", body)
	}
	if strings.Contains(body, "Hidden Address Sentinel") {
		t.Fatalf("calendar feed exposed private address")
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
	nextID        byte
	usersByID     map[string]UserWithPassword
	usersByEmail  map[string]UserWithPassword
	sessions      map[string]Session
	playgroups    []Playgroup
	events        map[string]Event
	eventsByToken map[string]Event
	locations     map[string]EventLocation
	hosts         map[string][]EventHost
	rsvps         map[string][]EventRSVP
}

func newFakeStore() *fakeStore {
	return &fakeStore{
		usersByID:     map[string]UserWithPassword{},
		usersByEmail:  map[string]UserWithPassword{},
		sessions:      map[string]Session{},
		events:        map[string]Event{},
		eventsByToken: map[string]Event{},
		locations:     map[string]EventLocation{},
		hosts:         map[string][]EventHost{},
		rsvps:         map[string][]EventRSVP{},
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

func (s *fakeStore) GetPlaygroupBySlugAndUser(_ context.Context, slug string, _ pgtype.UUID) (Playgroup, error) {
	for _, playgroup := range s.playgroups {
		if playgroup.Slug == slug {
			return playgroup, nil
		}
	}
	return Playgroup{}, pgx.ErrNoRows
}

func (s *fakeStore) CreateEvent(_ context.Context, params CreateEventParams) (Event, error) {
	event := Event{
		ID:          s.nextUUID(),
		PlaygroupID: params.PlaygroupID,
		Title:       params.Title,
		Description: params.Description,
		StartTime:   params.StartTime,
		EndTime:     params.EndTime,
		Visibility:  params.Visibility,
		InviteToken: params.InviteToken,
		MemberRole:  "owner",
	}
	if params.Location != nil {
		location := EventLocation{
			ID:            s.nextUUID(),
			Name:          params.Location.Name,
			AddressLine1:  params.Location.AddressLine1,
			AddressLine2:  params.Location.AddressLine2,
			City:          params.Location.City,
			StateProvince: params.Location.StateProvince,
			PostalCode:    params.Location.PostalCode,
			Country:       params.Location.Country,
			Notes:         params.Location.Notes,
		}
		event.LocationID = location.ID
		s.locations[uuidKey(event.ID)] = location
	}
	if params.AddressVisibility != "" {
		s.hosts[uuidKey(event.ID)] = []EventHost{{
			UserID:            params.CreatedBy,
			AddressVisibility: params.AddressVisibility,
		}}
	}
	s.events[uuidKey(event.ID)] = event
	s.eventsByToken[event.InviteToken] = event
	return event, nil
}

func (s *fakeStore) GetEventByID(_ context.Context, id pgtype.UUID) (Event, error) {
	event, ok := s.events[uuidKey(id)]
	if !ok {
		return Event{}, pgx.ErrNoRows
	}
	return event, nil
}

func (s *fakeStore) GetEventForUser(_ context.Context, id pgtype.UUID, _ pgtype.UUID) (Event, error) {
	event, ok := s.events[uuidKey(id)]
	if !ok {
		return Event{}, pgx.ErrNoRows
	}
	if event.MemberRole == "" {
		event.MemberRole = "member"
	}
	return event, nil
}

func (s *fakeStore) GetEventByToken(_ context.Context, token string) (Event, error) {
	event, ok := s.eventsByToken[token]
	if !ok {
		return Event{}, pgx.ErrNoRows
	}
	return event, nil
}

func (s *fakeStore) GetEventLocationForEvent(_ context.Context, eventID pgtype.UUID) (EventLocation, error) {
	location, ok := s.locations[uuidKey(eventID)]
	if !ok {
		return EventLocation{}, pgx.ErrNoRows
	}
	return location, nil
}

func (s *fakeStore) ListEventHosts(_ context.Context, eventID pgtype.UUID) ([]EventHost, error) {
	return append([]EventHost(nil), s.hosts[uuidKey(eventID)]...), nil
}

func (s *fakeStore) ListEventsForPlaygroup(_ context.Context, playgroupID pgtype.UUID) ([]Event, error) {
	events := []Event{}
	for _, event := range s.events {
		if event.PlaygroupID == playgroupID {
			events = append(events, event)
		}
	}
	return events, nil
}

func (s *fakeStore) UpdateEvent(ctx context.Context, params UpdateEventParams) (Event, error) {
	return Event{}, nil
}

func (s *fakeStore) GetEventRSVP(_ context.Context, eventID pgtype.UUID, userID pgtype.UUID) (EventRSVP, error) {
	for _, rsvp := range s.rsvps[uuidKey(eventID)] {
		if rsvp.UserID == userID {
			return rsvp, nil
		}
	}
	return EventRSVP{}, pgx.ErrNoRows
}

func (s *fakeStore) ListEventRSVPs(_ context.Context, eventID pgtype.UUID) ([]EventRSVP, error) {
	return append([]EventRSVP(nil), s.rsvps[uuidKey(eventID)]...), nil
}

func (s *fakeStore) CreateEventRSVP(_ context.Context, params CreateEventRSVPParams) (EventRSVP, error) {
	rsvp := EventRSVP{
		ID:                  s.nextUUID(),
		EventID:             params.EventID,
		UserID:              params.UserID,
		GuestName:           params.GuestName,
		Status:              params.Status,
		ArrivalTime:         params.ArrivalTime,
		LeavingTime:         params.LeavingTime,
		GuestCount:          params.GuestCount,
		TravelBufferMinutes: params.TravelBufferMinutes,
		Notes:               params.Notes,
	}
	s.rsvps[uuidKey(params.EventID)] = append(s.rsvps[uuidKey(params.EventID)], rsvp)
	return rsvp, nil
}

func (s *fakeStore) UpdateEventRSVP(ctx context.Context, params UpdateEventRSVPParams) (EventRSVP, error) {
	return EventRSVP{}, nil
}

func (s *fakeStore) EnqueueEmailDelivery(ctx context.Context, params EnqueueEmailParams) error {
	return nil
}

func (s *fakeStore) seedEvent(token string, visibility string, addressVisibility string) Event {
	playgroup := Playgroup{ID: s.nextUUID(), Name: "Test Crew", Slug: "test-crew", Role: "owner"}
	s.playgroups = append(s.playgroups, playgroup)
	event := Event{
		ID:          s.nextUUID(),
		PlaygroupID: playgroup.ID,
		Title:       "Commander Night",
		Description: "Bring two decks.",
		StartTime:   time.Date(2026, 5, 20, 19, 0, 0, 0, time.UTC),
		Visibility:  visibility,
		InviteToken: token,
		MemberRole:  "member",
	}
	location := EventLocation{
		ID:           s.nextUUID(),
		Name:         "Kitchen Table",
		AddressLine1: "Hidden Address Sentinel",
		City:         "Nashville",
		PostalCode:   "37201",
	}
	event.LocationID = location.ID
	s.events[uuidKey(event.ID)] = event
	s.eventsByToken[token] = event
	s.locations[uuidKey(event.ID)] = location
	s.hosts[uuidKey(event.ID)] = []EventHost{{
		UserID:            s.nextUUID(),
		AddressVisibility: addressVisibility,
	}}
	return event
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

func uuidString(t *testing.T, id pgtype.UUID) string {
	t.Helper()
	value, err := id.Value()
	if err != nil {
		t.Fatalf("uuid value: %v", err)
	}
	text, ok := value.(string)
	if !ok {
		t.Fatalf("uuid value was %T", value)
	}
	return text
}
