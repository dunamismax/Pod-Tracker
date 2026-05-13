package main

import (
	"log/slog"
	"os"

	"github.com/dunamismax/pod-tracker/internal/config"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg := config.Load()

	logger.Info("pod_tracker_worker_ready", "environment", cfg.Environment)
}
