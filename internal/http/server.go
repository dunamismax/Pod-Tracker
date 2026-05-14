package httpserver

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"html/template"
	"log/slog"
	"net/http"
	"path/filepath"
	"time"

	"github.com/dunamismax/pod-tracker/internal/config"
)

type contextKey string

const (
	requestIDKey        contextKey = "request_id"
	currentUserKey      contextKey = "current_user"
	sessionTokenHashKey contextKey = "session_token_hash"
)

type Server struct {
	cfg             config.Config
	logger          *slog.Logger
	readinessChecks []ReadinessCheck
	templates       *template.Template
	store           Store
}

type ReadinessCheck struct {
	Name  string
	Check func(context.Context) error
}

type Option func(*Server)

func WithReadinessCheck(name string, check func(context.Context) error) Option {
	return func(s *Server) {
		s.readinessChecks = append(s.readinessChecks, ReadinessCheck{
			Name:  name,
			Check: check,
		})
	}
}

func WithStore(store Store) Option {
	return func(s *Server) {
		s.store = store
	}
}

func New(cfg config.Config, logger *slog.Logger, opts ...Option) (*Server, error) {
	templates, err := template.ParseFiles(filepath.Join(cfg.TemplateDir, "base.html"))
	if err != nil {
		return nil, fmt.Errorf("parse templates: %w", err)
	}

	server := &Server{
		cfg:       cfg,
		logger:    logger,
		templates: templates,
	}
	for _, opt := range opts {
		opt(server)
	}

	return server, nil
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /static/", http.StripPrefix("/static/", http.FileServer(http.Dir(s.cfg.StaticDir))))
	mux.HandleFunc("GET /", s.home)
	mux.HandleFunc("GET /home", s.dashboard)
	mux.HandleFunc("GET /signup", s.signupForm)
	mux.HandleFunc("POST /signup", s.signup)
	mux.HandleFunc("GET /login", s.loginForm)
	mux.HandleFunc("POST /login", s.login)
	mux.HandleFunc("POST /logout", s.logout)
	mux.HandleFunc("GET /settings", s.settings)
	mux.HandleFunc("GET /playgroups", s.playgroups)
	mux.HandleFunc("POST /playgroups", s.createPlaygroup)
	mux.HandleFunc("GET /playgroups/{slug}", s.playgroupView)
	mux.HandleFunc("GET /playgroups/{slug}/events/new", s.newEventForm)
	mux.HandleFunc("POST /playgroups/{slug}/events", s.createEvent)
	mux.HandleFunc("GET /events/{id}", s.eventView)
	mux.HandleFunc("GET /events/{id}/edit", s.editEventForm)
	mux.HandleFunc("POST /events/{id}/edit", s.updateEvent)
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.HandleFunc("GET /readyz", s.readyz)

	return s.requestID(s.logRequests(s.loadSession(s.csrfProtection(mux))))
}

func (s *Server) home(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	data := s.newTemplateData(w, r)
	s.render(w, r, http.StatusOK, "home.html", data)
}

func (s *Server) healthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}` + "\n"))
}

func (s *Server) readyz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	for _, readinessCheck := range s.readinessChecks {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		err := readinessCheck.Check(ctx)
		cancel()
		if err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = fmt.Fprintf(w, `{"status":"not_ready","check":%q}`+"\n", readinessCheck.Name)
			s.logger.Warn("readiness check failed",
				"check", readinessCheck.Name,
				"err", err,
				"request_id", RequestID(r.Context()),
			)
			return
		}
	}

	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ready"}` + "\n"))
}

func (s *Server) requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := r.Header.Get("X-Request-ID")
		if requestID == "" {
			requestID = newRequestID()
		}

		w.Header().Set("X-Request-ID", requestID)
		ctx := context.WithValue(r.Context(), requestIDKey, requestID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(recorder, r)

		s.logger.Info("http_request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", recorder.status,
			"duration_ms", time.Since(start).Milliseconds(),
			"request_id", RequestID(r.Context()),
		)
	})
}

func RequestID(ctx context.Context) string {
	if requestID, ok := ctx.Value(requestIDKey).(string); ok {
		return requestID
	}
	return ""
}

func CurrentUser(ctx context.Context) (User, bool) {
	user, ok := ctx.Value(currentUserKey).(User)
	return user, ok
}

func SessionTokenHash(ctx context.Context) ([]byte, bool) {
	hash, ok := ctx.Value(sessionTokenHashKey).([]byte)
	return hash, ok
}

func newRequestID() string {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(bytes[:])
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func (s *Server) render(w http.ResponseWriter, r *http.Request, status int, page string, data any) {
	tmpl, err := s.templates.Clone()
	if err != nil {
		s.logger.Error("clone templates", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "template error", http.StatusInternalServerError)
		return
	}
	if _, err := tmpl.ParseFiles(filepath.Join(s.cfg.TemplateDir, page)); err != nil {
		s.logger.Error("parse page template", "page", page, "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "template error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	if err := tmpl.ExecuteTemplate(w, "base", data); err != nil {
		s.logger.Error("render template", "page", page, "err", err, "request_id", RequestID(r.Context()))
	}
}
