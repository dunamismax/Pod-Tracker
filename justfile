set dotenv-load := true

database_url := env_var_or_default("POD_TRACKER_DATABASE_URL", "postgres://pod_tracker:pod_tracker@localhost:5432/pod_tracker?sslmode=disable")
migration_database_url := env_var_or_default("POD_TRACKER_MIGRATION_DATABASE_URL", database_url)
export DATABASE_URL := env_var_or_default("DATABASE_URL", database_url)
goose := "go run github.com/pressly/goose/v3/cmd/goose@v3.27.1"

default:
  just --list

run:
  cargo run -p pod-web --bin pod-tracker-web

worker:
  cargo run -p pod-worker --bin pod-tracker-worker

release:
  cargo build --locked --release -p pod-web --bin pod-tracker-web -p pod-worker --bin pod-tracker-worker -p pod-db --bin pod-tracker-migrate

fmt:
  cargo fmt --all

check:
  cargo fmt --all --check
  cargo clippy --workspace --all-targets --all-features -- -D warnings
  cargo test --workspace --all-features
  cargo build --workspace

test:
  cargo test --workspace --all-features

legacy-go-test:
  go test ./...

db-create:
  createdb pod_tracker

db-drop:
  dropdb --if-exists pod_tracker

db-reset: db-drop db-create migrate-up

migrate-up:
  POD_TRACKER_MIGRATION_DATABASE_URL="{{migration_database_url}}" cargo run -p pod-db --bin pod-tracker-migrate -- up

migrate-status:
  POD_TRACKER_MIGRATION_DATABASE_URL="{{migration_database_url}}" cargo run -p pod-db --bin pod-tracker-migrate -- status

migrate-down:
  @echo "SQLx migrations are forward-only; write a new migration instead." >&2
  @exit 1

migrate-smoke:
  #!/usr/bin/env bash
  set -euo pipefail
  db="pod_tracker_smoke_$(date +%s)"
  createdb "$db"
  trap 'dropdb --if-exists "$db" >/dev/null' EXIT
  {{goose}} -dir migrations postgres "postgres://$(whoami)@localhost:5432/$db?sslmode=disable" up
  psql -d "$db" -Atc "select extname from pg_extension where extname in ('pgcrypto','pg_trgm','pg_stat_statements','btree_gin') order by extname"

sqlx-migrate-smoke:
  #!/usr/bin/env bash
  set -euo pipefail
  db="pod_tracker_sqlx_smoke_$(date +%s)"
  createdb "$db"
  trap 'dropdb --if-exists "$db" >/dev/null' EXIT
  for migration in crates/pod-db/migrations/*.sql; do
    psql -v ON_ERROR_STOP=1 -d "$db" -f "$migration" >/dev/null
  done
  psql -d "$db" -Atc "select extname from pg_extension where extname in ('pgcrypto','pg_trgm','pg_stat_statements','btree_gin') order by extname"
  DATABASE_URL="postgres://$(whoami)@localhost:5432/$db?sslmode=disable" cargo check -p pod-db --all-targets --all-features
