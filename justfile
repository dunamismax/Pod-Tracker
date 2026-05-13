set dotenv-load := true

database_url := env_var_or_default("POD_TRACKER_DATABASE_URL", "postgres://pod_tracker:pod_tracker@localhost:5432/pod_tracker?sslmode=disable")
migration_database_url := env_var_or_default("POD_TRACKER_MIGRATION_DATABASE_URL", database_url)
goose := "go run github.com/pressly/goose/v3/cmd/goose@v3.27.1"
sqlc := "go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.30.0"

default:
  just --list

run:
  go run ./cmd/pod-tracker-web

worker:
  go run ./cmd/pod-tracker-worker

fmt:
  gofmt -w $(find . -name '*.go' -not -path './vendor/*')

generate:
  {{sqlc}} generate

check:
  {{sqlc}} generate
  go test ./...

test:
  go test ./...

db-create:
  createdb pod_tracker

db-drop:
  dropdb --if-exists pod_tracker

db-reset: db-drop db-create migrate-up

migrate-up:
  {{goose}} -dir migrations postgres "{{migration_database_url}}" up

migrate-status:
  {{goose}} -dir migrations postgres "{{migration_database_url}}" status

migrate-down:
  {{goose}} -dir migrations postgres "{{migration_database_url}}" down

migrate-smoke:
  #!/usr/bin/env bash
  set -euo pipefail
  db="pod_tracker_smoke_$(date +%s)"
  createdb "$db"
  trap 'dropdb --if-exists "$db" >/dev/null' EXIT
  {{goose}} -dir migrations postgres "postgres://$(whoami)@localhost:5432/$db?sslmode=disable" up
  psql -d "$db" -Atc "select extname from pg_extension where extname in ('pgcrypto','pg_trgm','pg_stat_statements','btree_gin') order by extname"
