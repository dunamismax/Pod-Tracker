package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/dunamismax/pod-tracker/internal/config"
	"github.com/dunamismax/pod-tracker/internal/db"
	"github.com/dunamismax/pod-tracker/internal/db/sqlc"
	"github.com/dunamismax/pod-tracker/internal/email"
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

	emailClient := email.NewClient(cfg.SMTP2GOAPIKey, cfg.SMTPSender)

	go runWorker(ctx, logger, pool, emailClient)

	<-ctx.Done()
	logger.Info("pod_tracker_worker_stopping")
}

func runWorker(ctx context.Context, logger *slog.Logger, pool *pgxpool.Pool, emailClient *email.Client) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	hostname, _ := os.Hostname()
	workerID := fmt.Sprintf("%s-%d", hostname, os.Getpid())

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			processJobs(ctx, logger, pool, emailClient, workerID)
		}
	}
}

func processJobs(ctx context.Context, logger *slog.Logger, pool *pgxpool.Pool, emailClient *email.Client, workerID string) {
	for {
		if ctx.Err() != nil {
			return
		}

		queries := dbsql.New(pool)
		
		// Attempt to acquire a job
		job, err := queries.AcquireNextBackgroundJob(ctx, pgtype.Text{String: workerID, Valid: true})
		if err != nil {
			if err != pgx.ErrNoRows {
				logger.Error("acquire background job", "err", err)
			}
			return // No more jobs or error
		}

		logger.Info("processing job", "job_id", uuidKey(job.ID), "type", job.JobType)

		var jobErr error
		switch job.JobType {
		case "send_email":
			jobErr = processSendEmailJob(ctx, logger, queries, emailClient, job.Payload)
		default:
			jobErr = fmt.Errorf("unknown job type: %s", job.JobType)
		}

		if jobErr != nil {
			logger.Error("job failed", "job_id", uuidKey(job.ID), "err", jobErr)
			errStr := pgtype.Text{String: jobErr.Error(), Valid: true}
			if err := queries.FailBackgroundJob(ctx, dbsql.FailBackgroundJobParams{
				ID:        job.ID,
				LastError: errStr,
			}); err != nil {
				logger.Error("failed to mark job as failed", "err", err)
			}
		} else {
			if err := queries.CompleteBackgroundJob(ctx, job.ID); err != nil {
				logger.Error("failed to complete job", "err", err)
			}
		}
	}
}

func processSendEmailJob(ctx context.Context, logger *slog.Logger, queries *dbsql.Queries, emailClient *email.Client, payload []byte) error {
	var data struct {
		EmailDeliveryID string `json:"email_delivery_id"`
	}
	if err := json.Unmarshal(payload, &data); err != nil {
		return fmt.Errorf("unmarshal payload: %w", err)
	}

	var deliveryID pgtype.UUID
	if err := deliveryID.Scan(data.EmailDeliveryID); err != nil {
		return fmt.Errorf("scan delivery id: %w", err)
	}

	delivery, err := queries.GetEmailDelivery(ctx, deliveryID)
	if err != nil {
		return fmt.Errorf("get email delivery: %w", err)
	}

	err = emailClient.Send(ctx, delivery.ToAddress, delivery.Subject, delivery.BodyText.String, delivery.BodyHtml.String)
	
	status := "sent"
	var errMsg pgtype.Text
	if err != nil {
		status = "failed"
		errMsg = pgtype.Text{String: err.Error(), Valid: true}
	}

	_, updateErr := queries.UpdateEmailDeliveryStatus(ctx, dbsql.UpdateEmailDeliveryStatusParams{
		ID:           delivery.ID,
		Status:       status,
		ErrorMessage: errMsg,
	})
	if updateErr != nil {
		logger.Error("update email delivery status", "err", updateErr)
	}

	return err
}

func uuidKey(id pgtype.UUID) string {
	var idStr string
	if b, err := id.Value(); err == nil && b != nil {
		idStr = b.(string)
	}
	return idStr
}
