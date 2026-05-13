package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/dunamismax/pod-tracker/internal/config"
	"github.com/dunamismax/pod-tracker/internal/db"
	httpserver "github.com/dunamismax/pod-tracker/internal/http"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg := config.Load()

	startupCtx, startupCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer startupCancel()

	pool, err := db.Connect(startupCtx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("connect database", "err", err)
		os.Exit(1)
	}
	if pool != nil {
		defer pool.Close()
	}

	options := []httpserver.Option{}
	if pool != nil {
		options = append(options, httpserver.WithStore(httpserver.NewPGStore(pool)))
		options = append(options, httpserver.WithReadinessCheck("database", func(ctx context.Context) error {
			return db.Check(ctx, pool)
		}))
	}

	server, err := httpserver.New(cfg, logger, options...)
	if err != nil {
		logger.Error("initialize server", "err", err)
		os.Exit(1)
	}

	httpServer := &http.Server{
		Addr:              cfg.Addr,
		Handler:           server.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	errs := make(chan error, 1)
	go func() {
		logger.Info("pod_tracker_web_starting", "addr", cfg.Addr, "environment", cfg.Environment)
		errs <- httpServer.ListenAndServe()
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	select {
	case err := <-errs:
		if err != nil && err != http.ErrServerClosed {
			logger.Error("server stopped", "err", err)
			os.Exit(1)
		}
	case sig := <-stop:
		logger.Info("shutdown requested", "signal", sig.String())
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(ctx); err != nil {
			logger.Error("graceful shutdown", "err", err)
			os.Exit(1)
		}
	}
}
