# Deployment

Ideal Magic's target deployment is a single self-hosted Ubuntu VM serving `ideal-magic.com` behind Caddy-managed TLS.

This document describes the intended production shape. It is not a runbook yet because the Docker Compose, Caddy, systemd, backup, and production deploy files have not been implemented.

## Target Architecture

- Ubuntu VM.
- Caddy as the public TLS reverse proxy for `ideal-magic.com`.
- Docker Compose for the Rails web process, worker process, PostgreSQL, and supporting services.
- Puma for Rails web serving.
- Solid Queue for background analysis and refresh jobs.
- PostgreSQL volume backups with documented restore.
- systemd units for service lifecycle.
- systemd timers or equivalent cron-compatible jobs for backups, Scryfall sync, and health checks.

## Runtime Processes

The expected process split:

- `web`: Rails app served by Puma.
- `worker`: Rails background jobs for imports, Scryfall refreshes, and analysis.
- `codex`: Codex App Server or isolated Codex worker runtime for ChatGPT/Codex account-auth AI evaluation.
- `db`: PostgreSQL.
- Optional internal support services only when they earn their complexity.

Caddy should normally live at the host edge and proxy to the app container.

## Environment Contract

The production environment should eventually document every required variable. Expected categories:

- Rails secret key base.
- Database URL or database credentials.
- Codex runtime path, Codex credential storage path, and account-auth isolation settings.
- App host and mailer URL options.
- SMTP settings for account emails.
- Scryfall sync settings.
- Rate-limit and quota settings.

Secrets must not be committed. `.env.example` should contain names and safe placeholder values only.

## Deploy Flow

The intended deploy flow:

1. Pull the current branch on the VM.
2. Build or pull Docker images.
3. Run database migrations.
4. Restart the web and worker services.
5. Check health endpoint.
6. Check logs for boot or migration errors.

The actual commands should be written after the Docker runtime exists.

## Backups And Restore

Backups should include PostgreSQL data and any Active Storage files that become durable product data.

Before public launch, the repo needs:

- Backup script.
- Restore script or documented restore command.
- systemd timer for scheduled backups.
- Retention policy.
- Restore drill into a fresh volume.

Backups are not complete until restore has been tested.

## Health Checks

The app exposes health and readiness endpoints:

- `/up` for process boot.
- `/ready` for database connectivity.

Caddy and deployment scripts should use these endpoints once implemented.
