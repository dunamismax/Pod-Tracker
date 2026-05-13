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

const requestIDKey contextKey = "request_id"

type Server struct {
	cfg             config.Config
	logger          *slog.Logger
	readinessChecks []ReadinessCheck
	templates       *template.Template
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

func New(cfg config.Config, logger *slog.Logger, opts ...Option) (*Server, error) {
	templates, err := template.ParseGlob(filepath.Join(cfg.TemplateDir, "*.html"))
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
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.HandleFunc("GET /readyz", s.readyz)

	return s.requestID(s.logRequests(mux))
}

func (s *Server) home(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	data := struct {
		Environment string
		RequestID   string
	}{
		Environment: s.cfg.Environment,
		RequestID:   RequestID(r.Context()),
	}
	if err := s.templates.ExecuteTemplate(w, "base", data); err != nil {
		s.logger.Error("render home", "err", err, "request_id", RequestID(r.Context()))
	}
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
