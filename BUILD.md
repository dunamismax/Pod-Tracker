# BUILD.md

Future build plan for Pod Tracker. `README.md` describes the current
product and `AGENTS.md` holds durable repo operating rules.

V1.0 is complete. Keep this file intentionally light until new work is
ready to plan; add future sections and phases here as ideas become
concrete enough to build and verify.

Last reviewed: 2026-05-21.

---

## Current State

- Rust/Axum/Leptos/sqlx/PostgreSQL is the live product stack.
- Production runs at [https://pod-tracker.app/](https://pod-tracker.app/)
  behind Caddy and systemd on Stephen's Ubuntu VM.
- SQLx migrations in `crates/pod-db/migrations/` are the canonical schema
  history.
- Optional pgvector setup remains outside default migrations in
  `crates/pod-db/optional-migrations/pgvector/`.
- Legacy Go, sqlc, Goose, HTMX templates, and duplicate Goose migrations
  have been removed from the repository.
- Do not deploy, run production migrations, restart services, change
  Caddy/systemd, or access production data without explicit approval.

## Verification

Normal Rust workspace gate:

```sh
git diff --check
just fmt
just check
just test
just sqlx-migrate-smoke
```

SQLx compile checks need `DATABASE_URL` pointed at a migrated local
PostgreSQL database whose role can introspect the application schemas.
Use real local PostgreSQL, not Docker PostgreSQL.

## Future Ideas

Add future roadmap sections here when they are ready to scope.

### Future Phase Template

- [ ] Define the user-facing outcome.
- [ ] Document privacy, operations, and database implications.
- [ ] Implement the narrowest useful slice.
- [ ] Verify with focused tests and the normal workspace gate.
