# Local Development

Pod Tracker uses the installed macOS PostgreSQL service. Do not use
Docker PostgreSQL for local development.

## Toolchain

Observed local baseline on 2026-05-13:

```sh
go version
psql --version
just --version
```

Expected:

```text
go1.26.3 darwin/arm64
PostgreSQL 17.9 Homebrew
just 1.51.0
```

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

Start the Homebrew PostgreSQL service if it is not already running:

```sh
brew services start postgresql@17
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

Goose is the canonical migration tool. SQL migrations live in
`migrations/` and use Goose annotations.

Useful commands:

```sh
just migrate-status
just migrate-up
just migrate-down
just migrate-smoke
```

`just migrate-smoke` creates a timestamped local smoke-test database,
applies all migrations with the current macOS user, checks required
extensions, and drops the smoke database on exit.

## SQL Generation

sqlc generates typed Go query code from migration-backed schema and SQL
files:

```sh
just generate
```

Generated code is committed so clean checkouts can build without a
separate generation step. `just check` runs generation before tests.

## Running

```sh
just run
just worker
```

The web server defaults to `http://localhost:8080`.
