package httpserver

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

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
