package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/dunamismax/pod-tracker/internal/config"
	"github.com/dunamismax/pod-tracker/internal/db"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg := config.Load()

	logger.Info("pod_tracker_worker_ready", "environment", cfg.Environment)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("failed to connect to database", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	go runWorker(ctx, logger, pool)

	<-ctx.Done()
	logger.Info("pod_tracker_worker_stopping")
}

func runWorker(ctx context.Context, logger *slog.Logger, pool *pgxpool.Pool) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			// Skeleton for processing jobs:
			// 1. SELECT id FROM ops.background_jobs WHERE run_at <= NOW() AND locked_at IS NULL ORDER BY run_at ASC LIMIT 1 FOR UPDATE SKIP LOCKED
			// 2. UPDATE ops.background_jobs SET locked_at = NOW() WHERE id = $1
			// 3. Process job based on job_type
			// 4. DELETE FROM ops.background_jobs WHERE id = $1 (if success)
			// 5. Or increment attempts and clear locked_at (if fail)
			logger.Debug("checking for background jobs")
		}
	}
}
