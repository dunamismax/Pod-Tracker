package httpserver

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/dunamismax/pod-tracker/internal/auth"
)

const sessionDuration = 30 * 24 * time.Hour

type templateData struct {
	Environment          string
	RequestID            string
	CSRFToken            string
	Error                string
	Email                string
	DisplayName          string
	CurrentUser          *User
	Playgroup            *Playgroup
	Playgroups           []Playgroup
	PlaygroupName        string
	PlaygroupDescription string
	Events               []Event
	Event                *Event
	RSVPs                []EventRSVP
	UserRSVP             *EventRSVP
}

func (s *Server) signupForm(w http.ResponseWriter, r *http.Request) {
	s.render(w, r, http.StatusOK, "signup.html", s.newTemplateData(w, r))
}

func (s *Server) signup(w http.ResponseWriter, r *http.Request) {
	if s.store == nil {
		http.Error(w, "database is not configured", http.StatusServiceUnavailable)
		return
	}

	data := s.newTemplateData(w, r)
	email := normalizeEmail(r.FormValue("email"))
	displayName := strings.TrimSpace(r.FormValue("display_name"))
	password := r.FormValue("password")
	data.Email = email
	data.DisplayName = displayName

	if email == "" || displayName == "" || password == "" {
		data.Error = "Email, display name, and password are required."
		s.render(w, r, http.StatusUnprocessableEntity, "signup.html", data)
		return
	}

	passwordHash, err := auth.HashPassword(password)
	if err != nil {
		if errors.Is(err, auth.ErrPasswordTooShort) {
			data.Error = "Password must be at least 12 characters."
			s.render(w, r, http.StatusUnprocessableEntity, "signup.html", data)
			return
		}
		s.logger.Error("hash signup password", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "signup failed", http.StatusInternalServerError)
		return
	}

	user, err := s.store.CreateUser(r.Context(), CreateUserParams{
		Email:        email,
		DisplayName:  displayName,
		PasswordHash: passwordHash,
	})
	if err != nil {
		if isUniqueViolation(err) {
			data.Error = "An account already exists for that email."
			s.render(w, r, http.StatusUnprocessableEntity, "signup.html", data)
			return
		}
		s.logger.Error("create user", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "signup failed", http.StatusInternalServerError)
		return
	}

	// Queue welcome email
	go func() {
		// Ideally this uses a background context, since request context will cancel
		ctx := context.Background()
		err := s.store.EnqueueEmailDelivery(ctx, EnqueueEmailParams{
			ToAddress: email,
			Subject:   "Welcome to Pod Tracker",
			TextBody:  "Welcome to Pod Tracker, " + displayName + "!\n\nYour account has been created successfully. You can now join playgroups and RSVP to events.",
		})
		if err != nil {
			s.logger.Error("enqueue welcome email", "err", err)
		}
	}()

	if err := s.startSession(w, r, user.ID); err != nil {
		s.logger.Error("start signup session", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "signup failed", http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/home", http.StatusSeeOther)
}

func (s *Server) loginForm(w http.ResponseWriter, r *http.Request) {
	s.render(w, r, http.StatusOK, "login.html", s.newTemplateData(w, r))
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	if s.store == nil {
		http.Error(w, "database is not configured", http.StatusServiceUnavailable)
		return
	}

	data := s.newTemplateData(w, r)
	email := normalizeEmail(r.FormValue("email"))
	password := r.FormValue("password")
	data.Email = email

	user, err := s.store.GetUserByEmail(r.Context(), email)
	if err != nil || !auth.CheckPassword(user.PasswordHash, password) {
		data.Error = "Email or password is incorrect."
		s.render(w, r, http.StatusUnprocessableEntity, "login.html", data)
		return
	}

	if err := s.startSession(w, r, user.ID); err != nil {
		s.logger.Error("start login session", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "login failed", http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/home", http.StatusSeeOther)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if s.store != nil {
		if tokenHash, ok := SessionTokenHash(r.Context()); ok {
			if err := s.store.RevokeSession(r.Context(), tokenHash); err != nil {
				s.logger.Warn("revoke session", "err", err, "request_id", RequestID(r.Context()))
			}
		}
	}

	http.SetCookie(w, s.expiredSessionCookie())
	http.Redirect(w, r, "/login", http.StatusSeeOther)
}

func (s *Server) settings(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}
	s.render(w, r, http.StatusOK, "settings.html", s.newTemplateData(w, r))
}

func (s *Server) startSession(w http.ResponseWriter, r *http.Request, userID pgtype.UUID) error {
	token, tokenHash, err := auth.NewSessionToken()
	if err != nil {
		return err
	}
	if err := s.store.CreateSession(r.Context(), CreateSessionParams{
		UserID:    userID,
		TokenHash: tokenHash,
		UserAgent: r.UserAgent(),
		IPAddress: remoteAddr(r),
		ExpiresAt: time.Now().Add(sessionDuration),
	}); err != nil {
		return err
	}

	http.SetCookie(w, s.sessionCookie(token))
	return nil
}

func (s *Server) loadSession(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.store == nil {
			next.ServeHTTP(w, r)
			return
		}

		cookie, err := r.Cookie(auth.SessionCookieName)
		if err != nil || cookie.Value == "" {
			next.ServeHTTP(w, r)
			return
		}
		tokenHash, err := auth.HashSessionToken(cookie.Value)
		if err != nil {
			http.SetCookie(w, s.expiredSessionCookie())
			next.ServeHTTP(w, r)
			return
		}

		session, err := s.store.GetSessionByTokenHash(r.Context(), tokenHash)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				http.SetCookie(w, s.expiredSessionCookie())
			} else {
				s.logger.Warn("load session", "err", err, "request_id", RequestID(r.Context()))
			}
			next.ServeHTTP(w, r)
			return
		}
		user, err := s.store.GetUserByID(r.Context(), session.UserID)
		if err != nil {
			s.logger.Warn("load session user", "err", err, "request_id", RequestID(r.Context()))
			next.ServeHTTP(w, r)
			return
		}

		ctx := r.Context()
		ctx = contextWithUser(ctx, user)
		ctx = contextWithSessionTokenHash(ctx, tokenHash)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *Server) requireUser(w http.ResponseWriter, r *http.Request) bool {
	if _, ok := CurrentUser(r.Context()); ok {
		return true
	}
	http.Redirect(w, r, "/login", http.StatusSeeOther)
	return false
}

func contextWithUser(ctx context.Context, user User) context.Context {
	return context.WithValue(ctx, currentUserKey, user)
}

func contextWithSessionTokenHash(ctx context.Context, tokenHash []byte) context.Context {
	return context.WithValue(ctx, sessionTokenHashKey, tokenHash)
}

func (s *Server) newTemplateData(w http.ResponseWriter, r *http.Request) templateData {
	data := templateData{
		Environment: s.cfg.Environment,
		RequestID:   RequestID(r.Context()),
		CSRFToken:   s.csrfToken(w, r),
	}
	if user, ok := CurrentUser(r.Context()); ok {
		data.CurrentUser = &user
	}
	return data
}

func (s *Server) sessionCookie(token string) *http.Cookie {
	return &http.Cookie{
		Name:     auth.SessionCookieName,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		Secure:   s.secureCookies(),
		SameSite: http.SameSiteLaxMode,
		Expires:  time.Now().Add(sessionDuration),
		MaxAge:   int(sessionDuration.Seconds()),
	}
}

func (s *Server) expiredSessionCookie() *http.Cookie {
	return &http.Cookie{
		Name:     auth.SessionCookieName,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		Secure:   s.secureCookies(),
		SameSite: http.SameSiteLaxMode,
		Expires:  time.Unix(0, 0),
		MaxAge:   -1,
	}
}

func (s *Server) secureCookies() bool {
	return s.cfg.Environment == "production"
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func remoteAddr(r *http.Request) *netip.Addr {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	addr, err := netip.ParseAddr(host)
	if err != nil {
		return nil
	}
	return &addr
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
