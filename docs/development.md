# Local Development

Pod Tracker uses an installed PostgreSQL service. Do not use Docker
PostgreSQL for local development.

## Toolchain

Observed local baseline on 2026-05-17:

```sh
rustc --version
cargo --version
psql --version
just --version
```

Current Rust rewrite baseline:

```text
rustc 1.95.0
cargo 1.95.0
PostgreSQL 18 Homebrew
```

The committed `rust-toolchain.toml` pins Rust 1.95.0 with `rustfmt` and
`clippy`. On the Ubuntu VM, use the system PostgreSQL packages and the
same database URLs from `.env.example`.

## Environment

Copy `.env.example` to `.env` and edit values for local credentials.
The example file contains no secrets.

```sh
cp .env.example .env
```

Default local database URL:

```text
postgres://pod_tracker:pod_tracker@localhost:5432/pod_tracker?sslmode=disable
```

The first migration creates extensions. `pg_stat_statements` usually
requires an admin/superuser role, so set `POD_TRACKER_MIGRATION_DATABASE_URL`
to a local admin connection string if the app role cannot create it.

## PostgreSQL

Start PostgreSQL if it is not already running.

On macOS with Homebrew:

```sh
brew services start postgresql@18
```

On Ubuntu:

```sh
sudo systemctl start postgresql
```

Create the app role once:

```sh
createuser --pwprompt pod_tracker
```

Create and migrate the development database:

```sh
just db-create
POD_TRACKER_MIGRATION_DATABASE_URL=postgres://$(whoami)@localhost:5432/pod_tracker?sslmode=disable just migrate-up
```

After the extension migration is applied, routine app runtime should use
`POD_TRACKER_DATABASE_URL`:

```sh
just migrate-up
```

Reset local development data:

```sh
just db-reset
```

`just db-reset` drops only the local `pod_tracker` database named in the
recipe. It is not a production command.

## Migrations

The current migration history is inherited from the Go reference
implementation and remains numbered as-is before production Rust cutover.
SQL migrations live in `migrations/` and still carry Goose annotations so
the existing production path can remain untouched while the Rust rewrite
comes up beside it.

The Rust `pod-db` crate also embeds the same migration directory through
`sqlx::migrate!` so the rewrite can move to a SQLx-owned migration
workflow when the cutover plan is explicit.

Useful commands:

```sh
just migrate-status
just migrate-up
just migrate-down
just migrate-smoke
```

`just migrate-smoke` creates a timestamped local smoke-test database,
applies all migrations with the current OS user, checks required
extensions, and drops the smoke database on exit. On Ubuntu, create a
matching PostgreSQL role for the OS user or adapt the recipe to a local
admin role before running it.

## SQL Generation

New Rust database access goes through `sqlx` in `crates/pod-db`. The old
`sqlc` output remains only as reference behavior until the Rust parity
work replaces it.

## Running

```sh
just run
just worker
```

The Rust web server defaults to `http://localhost:8080`. With no
`POD_TRACKER_DATABASE_URL`, `/healthz` can still report process health
and `/readyz` reports that database readiness cannot be proven.

## Verification

Use the Rust workspace gate for normal work:

```sh
just fmt
just check
just test
```

Use `just legacy-go-test` only when comparing or stabilizing reference
behavior from the old Go implementation.
