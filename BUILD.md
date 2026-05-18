# BUILD.md

Active build plan for Pod Tracker. `README.md` introduces the product.
`AGENTS.md` holds durable repo operating rules. This file tracks current
state, the Rust rewrite, PostgreSQL design, product phases, and
verification.

Treat unchecked boxes as plan. Move stable material into `docs/`,
`README.md`, or runbooks as the implementation matures.

Last reviewed: 2026-05-18.

---

## Current Baseline

- Repository exists with MIT license.
- `origin` fetches from GitHub and pushes to GitHub plus Codeberg.
- Public production domain is [https://pod-tracker.app/](https://pod-tracker.app/).
- The old idea document has been distilled into `README.md`,
  `BUILD.md`, and `AGENTS.md`.
- A Go web and worker implementation currently exists with local
  HTMX/plain CSS, PostgreSQL migrations, sqlc typed queries,
  identity/session schema, signup/login/logout, CSRF-protected forms,
  playgroups, events, public-safe event pages, invite-token RSVP flow,
  authenticated iCalendar feed, readiness checks, Caddy/systemd deploy
  assets, and backup/restore scripts.
- The next active work is a full rewrite to Stephen's Rust web stack:
  Rust workspace, Axum, Leptos, Tokio, PostgreSQL, Caddy, and systemd.

The Go implementation is a reference for behavior and production shape,
not the future stack. Do not add new product surface to Go unless it is
needed to understand, stabilize, or safely replace existing behavior.

---

## Stack Direction

- **Rust** for all application and worker binaries.
- **Axum** for HTTP routing, middleware, request extraction, and API
  edges.
- **Leptos** for server-rendered application UI, reusable components,
  form flows, and narrowly hydrated interactions where they earn their
  place.
- **PostgreSQL** as the system of record and main product engine.
- **Tokio** as the async runtime.
- **sqlx** preferred for explicit SQL, compile-time checked queries where
  practical, migrations, PostgreSQL pools, and repository code. Use a
  different Rust typed-SQL workflow only if it is documented in this file
  first.
- **tower**, **tower-http**, and **tracing** for middleware,
  instrumentation, compression, static assets, request IDs, and
  production logs.
- **tracing-subscriber** first for local and production logs; add
  OpenTelemetry only after request/job spans are stable and there is a real
  collector or exporter target.
- **figment** or **config** only if environment, file, tenant, and job
  settings outgrow the current explicit configuration model.
- **PostgreSQL `LISTEN` / `NOTIFY`** for lightweight realtime fanout.
- **SSE** for browser event streams.
- **PostgreSQL-backed job tables** using `FOR UPDATE SKIP LOCKED` for
  imports, reminders, exports, email delivery, and materialized-view
  refreshes.
- **Caddy + systemd + Ubuntu VM** for production.
- **No Docker PostgreSQL.** Local development uses the installed macOS
  PostgreSQL service. Production uses a real PostgreSQL service on the
  Ubuntu VM.

Current local baseline observed on 2026-05-17:

```text
PostgreSQL server: 17.9 Homebrew
psql: 17.10 Homebrew
```

FileFerry is the local example for Stephen's Rust web preferences:

- Cargo workspace with crates under `crates/`.
- Rust 2024 edition and workspace-managed dependencies.
- Axum server binary using Tokio.
- Leptos SSR rendered from Rust components.
- Plain, restrained CSS assets owned by the web crate.
- `just fmt`, `just check`, and focused site/server smoke tests.

Re-check current primary docs before locking exact crate versions during
implementation.

---

## Product Invariants

- Game night planning is the center of the product.
- Deckbuilding supports event planning; it does not dominate the MVP.
- PostgreSQL is the source of truth for state, permissions, analytics,
  search, jobs, and history.
- Host addresses are sensitive and never globally visible.
- Guests see only the event scope they were invited into.
- Public pages use tokenized, public-safe views or equivalent scoped
  authorization.
- Competitive rankings are optional; default analytics emphasize meta
  health, variety, attendance, matchup freshness, and planning.
- Scryfall raw payloads are stored in JSONB alongside normalized fields.
- Commander Brackets and Game Changers are versioned data, not hard-coded
  eternal constants.
- Do not start with AI, pgvector, paid billing, native mobile apps, push
  notifications, or a full Moxfield replacement.

---

## PostgreSQL Design

Required extensions:

```sql
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists pg_stat_statements;
create extension if not exists btree_gin;
```

Later extensions:

```sql
create extension if not exists vector;
create extension if not exists postgis;
```

Use `vector` only after the core product and SQL Observatory are useful.
Use PostGIS only when distance, map, or traffic-aware leave-time features
earn it.

Recommended schemas:

```text
app     -- stable app-facing views and functions
core    -- users, playgroups, memberships, events, RSVPs, pods, games
mtg     -- Scryfall cards, decks, decklists, legalities, Game Changers
meta    -- materialized views, matchup summaries, pod scoring inputs
ops     -- jobs, reminders, imports, email deliveries, maintenance
audit   -- append-only event history
search  -- search documents and indexes
```

Core table groups:

- Identity: `users`, `sessions`, `accounts`, `auth_identities`.
- Playgroups: `playgroups`, `playgroup_memberships`,
  `playgroup_invites`, `playgroup_settings`, `house_rules`.
- Events: `events`, `event_locations`, `event_hosts`, `event_rsvps`,
  `event_guests`, `event_reminders`, `event_deck_declarations`.
- Pods and games: `pods`, `pod_seats`, `games`, `game_players`,
  `game_results`, `game_notes`.
- Decks and MTG data: `decks`, `deck_versions`, `deck_cards`,
  `deck_tags`, `deck_bracket_snapshots`, `cards`, `card_faces`,
  `card_printings`, `card_legalities`, `scryfall_imports`.
- Commander brackets: `commander_bracket_versions`,
  `game_changer_lists`, `game_changer_cards`,
  `deck_game_changer_snapshots`.
- Collection: `collections`, `collection_cards`, `wishlists`,
  `proxy_lists`.
- Operations: `background_jobs`, `notifications`, `email_deliveries`,
  `calendar_feeds`, `audit_events`, `search_documents`.

Database rules:

- Migrations are the canonical schema history.
- Prefer forward-only migrations once production data exists.
- Use UUID primary keys with time-ordered UUIDs where practical.
- Add database constraints for invariants the database can enforce.
- Prefer check constraints or lookup tables over unchecked strings.
- Use RLS, scoped queries, or public-safe views for tenant and guest
  boundaries.
- Keep raw Scryfall JSONB payloads, but normalize the columns needed for
  search, filtering, legality, and analytics.
- Materialized views should power expensive dashboard and pairing
  summaries.
- Test migrations against a real PostgreSQL database.

---

## Target Source Layout

```text
Cargo.toml
rust-toolchain.toml
crates/
  pod-core/          domain types, validation, scoring interfaces
  pod-db/            sqlx pool, migrations, repositories, transactions
  pod-web/           Axum router, Leptos SSR UI, assets, auth/session edge
  pod-worker/        job runner, imports, reminders, materialized refreshes
  pod-observatory/   SQL examples, explain helpers, scrubbed demo fixtures
xtask/               checks, fixtures, release/deploy automation when useful
migrations/
deploy/
  caddy/
  systemd/
  scripts/
docs/
  architecture.md
  database.md
  development.md
  deployment.md
  operations.md
  privacy.md
tests/
  playwright/
justfile
```

Keep web UI code in Rust/Leptos unless a small static JavaScript file is
the simplest honest way to support a feature. Do not introduce a
JavaScript application framework.

---

## Target Routes

Public:

```text
GET /                         product and live app entry
GET /about
GET /roadmap
GET /status
GET /healthz
GET /readyz
GET /e/{publicToken}          public-safe event page
GET /rsvp/{inviteToken}       guest RSVP flow
```

Authentication:

```text
GET  /signup
POST /signup
GET  /login
POST /login
POST /logout
GET  /settings
```

Application:

```text
GET  /home
GET  /playgroups
GET  /playgroups/{slug}
GET  /events
GET  /events/{id}
GET  /events/{id}/pods
GET  /decks
GET  /decks/{id}
GET  /cards
GET  /meta
GET  /observatory
GET  /events/stream
```

State-changing actions should be form posts, Leptos actions, or
progressively enhanced Rust-owned interactions with CSRF protection and
clear authorization checks.

---

## Rewrite Strategy

The Rust rewrite should preserve behavior before adding new scope.

- Port current Go behavior first: auth, sessions, playgroups, events,
  host-address privacy, public event pages, invite RSVP, calendar feeds,
  readiness, worker skeleton, Caddy/systemd, backups, and restore docs.
- Treat the Go database schema as observed context. Keep migrations
  compatible where practical, but do not keep awkward Go-era names or
  shapes if a documented Rust migration plan produces a better durable
  schema before real user data depends on it.
- Do not run production migrations, alter production data, or switch
  Caddy from Go to Rust without explicit approval.
- Run the Rust web service beside the Go service on a separate local or
  production port until parity checks pass.
- Keep the Go service available as rollback during production cutover.
- After the Rust app is live and verified, remove Go code, sqlc config,
  old templates, and old deployment units in one focused cleanup pass.

---

## Phases

Ordered intent, not rigid sequence. Each phase should leave the repo in a
state where documented verification passes on a clean checkout.

### Phase 0 - Rust Replan

- [x] Preserve product scope from the Go-oriented build plan.
- [x] Rewrite `README.md`, `BUILD.md`, and `AGENTS.md` around Rust,
      Leptos, Axum, and PostgreSQL.
- [x] Record that the existing Go app is reference behavior, not the
      future implementation path.

### Phase 1 - Rust Workspace Foundation

- [x] Add `rust-toolchain.toml`.
- [ ] Replace Go module metadata with a Cargo workspace.
- [x] Add crates: `pod-core`, `pod-db`, `pod-web`, `pod-worker`, and
      `xtask` only when it earns its keep.
- [x] Add workspace dependency policy and Rust 2024 edition.
- [x] Add `pod-web` Axum server binary with Tokio.
- [x] Add config loading from environment.
- [x] Add structured tracing, request IDs, panic behavior, and log
      redaction basics.
- [x] Add `/healthz` and `/readyz`.
- [x] Add Leptos SSR base layout, public home page, and static CSS asset
      pipeline.
- [x] Add `just run`, `just worker`, `just fmt`, `just check`, and
      `just test`.
- [x] Update CI from Go/sqlc checks to Rust workspace checks.

### Phase 2 - PostgreSQL, Migrations, And Typed SQL

- [x] Document Rust local development in `docs/development.md` while
      preserving the no-Docker PostgreSQL rule.
- [x] Decide whether to continue the existing migration numbering or
      start a clean Rust-compatible migration history before production
      data matters; document the choice here.
- [x] Wire sqlx migrations and PostgreSQL pool management.
- [x] Keep or recreate required extension migration:
      `pgcrypto`, `pg_trgm`, `pg_stat_statements`, `btree_gin`.
- [x] Add typed query coverage for health/readiness and base identity
      flows.
- [x] Add transaction helper and repository boundaries in `pod-db`.
- [x] Add migration smoke test against local real PostgreSQL.
- [x] Add sqlx offline metadata or an equivalent reproducible query-check
      workflow if used by CI.

### Phase 3 - Identity, Sessions, And Playgroups Parity

- [x] Port users, sessions, accounts, and auth identity schema.
- [x] Add Argon2id password hashing or document a better Rust password
      hashing choice.
- [x] Port signup, login, logout, and settings.
- [x] Add secure, HttpOnly, same-site session cookies.
- [x] Add CSRF protection for state-changing forms and Leptos actions.
- [x] Port playgroups, memberships, invites, roles, settings, and house
      rules.
- [x] Port owner/admin/member/host/guest/viewer role checks.
- [x] Port authenticated dashboard.
- [x] Add tests for auth, sessions, CSRF, and playgroup access.

### Phase 4 - Events, Hosts, RSVPs, And Calendar Parity

- [x] Port event, host, location, RSVP, guest, and reminder tables.
- [x] Port event creation and edit flow.
- [x] Port host address visibility rules.
- [x] Port RSVP states: yes, maybe, no, waitlist.
- [x] Capture arrival time, leaving time, guest count, travel buffer, and
      notes.
- [x] Port public-safe event page and invite-token RSVP flow.
- [x] Port authenticated iCalendar feed.
- [x] Port reminder job skeleton and email delivery log.
- [x] Port readiness checks for DB, migrations, jobs, and email tables.
- [x] Add tests proving address visibility, guest scoping, and calendar
      feed authorization.

### Phase 5 - Rust Deployment Cutover

- [x] Add Rust release build path for `pod-tracker-web` and
      `pod-tracker-worker`.
- [x] Update Caddy config for the Rust web service port while preserving
      a rollback path.
- [x] Update systemd units for Rust binaries.
- [x] Update deployment script for Cargo release builds, migrations, and
      service restart order.
- [x] Update production environment template without secrets.
- [x] Re-run backup and restore docs against the Rust deployment path.
- [x] Smoke the Rust service locally.
- [ ] With explicit approval, run production cutover from Go to Rust.
- [ ] After verified cutover, remove Go code, `go.mod`, `go.sum`,
      `sqlc.yaml`, generated sqlc files, old Go templates, and Go-specific
      deploy instructions.

### Phase 6 - Deck Registry And Event Declarations

- [x] Add deck registry with commander, color identity, claimed bracket,
      archetype, tags, visibility, active/retired state, and notes.
- [x] Add deck metadata flags: Game Changers count, infinite combo, fast
      mana, tutors density, extra turns, mass land denial, and salt notes.
- [x] Add deck visibility: private, playgroup, public.
- [x] Add event deck declarations with preference and testing notes.
- [x] Add basic deck search.
- [x] Add tests for deck ownership, visibility, and declarations.

### Phase 7 - Pod Generation

- [x] Add pod and pod seat tables.
- [x] Add pod states: proposed, locked, active, completed, cancelled.
- [x] Add SQL-backed candidate generation for confirmed attendees.
- [x] Score pod size fit, bracket compatibility, repeated player pairs,
      repeated deck matchups, guest placement, and availability windows.
- [x] Allow admin manual edits and manual locks.
- [x] Publish pod assignments and notify players.
- [x] Add SQL Observatory entry for the pod candidate and scoring query.
- [x] Add tests covering generation, constraints, locks, and permissions.

### Phase 8 - Game Logging

- [ ] Add games, game players, results, notes, and event completion.
- [ ] Support result types: normal win, combo win, combat win,
      concession, draw, time called, unfinished, archenemy win, team win.
- [ ] Capture winner, turn count, duration, first player, elimination
      order, tags, and notes where provided.
- [ ] Keep logging fast enough to use between games.
- [ ] Update matchup history after each logged game.
- [ ] Add tests for game logging and event history.

### Phase 9 - Scryfall Import And Card Search

- [ ] Add Scryfall bulk import job.
- [ ] Store raw Scryfall JSONB payloads.
- [ ] Normalize cards, faces, printings, legalities, prices, and search
      documents.
- [ ] Track import version and source metadata.
- [ ] Add full-text card search.
- [ ] Add `pg_trgm` fuzzy name search.
- [ ] Add filters for color identity, commander legality, mana value,
      type, price, and Game Changer status.
- [ ] Add SQL Observatory entries for fuzzy and full-text search.
- [ ] Add tests for imports, search ranking, and legality filters.

### Phase 10 - Decklist Import, Export, And Bracket Checks

- [ ] Add plain-text decklist paste/import.
- [ ] Match card names through exact, normalized, and fuzzy lookup.
- [ ] Detect commander(s) and color identity.
- [ ] Add Game Changers version tables.
- [ ] Count Game Changers per deck version.
- [ ] Show bracket-relevant warnings.
- [ ] Export plain-text, Moxfield-compatible, and
      Archidekt-compatible lists.
- [ ] Snapshot deck bracket analysis over time.
- [ ] Add tests for parsing, matching, warnings, and exports.

### Phase 11 - Meta Dashboard

- [ ] Add materialized views for attendance, deck win rates, player win
      rates, commander popularity, bracket distribution, color identity,
      archetypes, matchup history, and stale decks.
- [ ] Add dashboard focused on meta health, variety, and planning.
- [ ] Make competitive ranking optional rather than the default lens.
- [ ] Refresh materialized views through background jobs.
- [ ] Add SQL Observatory entries for the dashboard views.
- [ ] Add tests for metrics and refresh behavior.

### Phase 12 - Collection Tracking

- [ ] Add collections and collection card quantities.
- [ ] Track printing, foil flag, condition, and location when provided.
- [ ] Show missing cards by deck.
- [ ] Generate proxy/print lists.
- [ ] Add wishlists.
- [ ] Add collection visibility and ownership checks.
- [ ] Add tests for collection calculations and privacy.

### Phase 13 - SQL Observatory

- [ ] Build `/observatory`.
- [ ] Show real SQL for pod generation, avoid-repeat pairing, bracket
      compatibility, fuzzy card search, Game Changers count, reminders,
      matchup history, and Scryfall JSONB exploration.
- [ ] Explain inputs, indexes, query plan shape, and output.
- [ ] Add safe sample data or scrubbed fixtures.
- [ ] Never expose private addresses, emails, phone numbers, invite
      tokens, or production logs.

### Phase 14 - Operations And Deployment

- [x] Keep Caddy config current for `pod-tracker.app`.
- [x] Keep systemd units current for Rust web and worker binaries.
- [x] Keep deployment script current for the Ubuntu VM.
- [x] Keep production environment template current without secrets.
- [x] Keep database migration step in deploy.
- [x] Keep `pg_dump` backup script current.
- [x] Keep restore script and restore drill documentation current.
- [x] Keep operations runbook in `docs/operations.md`.
- [x] Add Caddy config validation.
- [ ] Add backup and restore drill from a real snapshot before public
      claims.

### Phase 15 - Hardening

- [ ] Add rate limits for signup, login, RSVP, invites, deck import,
      search, and admin actions.
- [ ] Add audit events for auth, membership, invite, event, RSVP, pod,
      address reveal, and result changes.
- [ ] Add structured error pages.
- [ ] Add log redaction checks.
- [ ] Add stable request, job, and database spans before considering
      OpenTelemetry export.
- [ ] Revisit config loading with `figment` or `config` if deployment,
      worker, email, and tenant settings become too broad for explicit env
      parsing.
- [ ] Add CSRF tests.
- [x] Add security header checks.
- [x] Add privacy model in `docs/privacy.md`.
- [ ] Add RLS or equivalent scoped-query tests for tenant, guest, public
      token, and host-address boundaries.

### Phase 16 - Advanced Intelligence

- [ ] Improve pod scoring with matchup freshness and deck variety.
- [ ] Add similar deck recommendations.
- [ ] Add collection-aware deck suggestions.
- [ ] Add optional pgvector semantic card/deck search.
- [ ] Add natural-language meta query research after SQL Observatory is
      useful.
- [ ] Document which recommendations are SQL, heuristic, semantic, or
      AI-backed.

### Phase 17 - Localization And Card Languages

- [ ] Decide supported application locales and document the policy before
      translating UI.
- [ ] Store user locale, timezone, and date/time display preferences.
- [ ] Keep event scheduling and calendar export correct across locale and
      timezone settings.
- [ ] Preserve Scryfall language fields for printings and names.
- [ ] Add multilingual card search where Scryfall data supports it.
- [ ] Add language-aware display for card names, printings, and decklist
      imports without breaking English canonical matching.
- [ ] Extract UI copy into a Rust-owned localization workflow once the
      core UI settles.
- [ ] Add tests for locale formatting, calendar output, multilingual card
      search, and decklist import matching.

---

## Verification

Narrowest useful command first, then broaden.

Docs-only work:

```sh
git diff --check
```

Normal Rust workspace gate once the skeleton exists:

```sh
just fmt
just check
just test
```

Expected `just check` shape:

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo build --workspace
```

Expected checks as the app matures:

- Rust formatting, clippy, and tests.
- sqlx query/migration checks.
- Migration validation against real PostgreSQL.
- Server startup smoke.
- `/healthz` and `/readyz`.
- Leptos component/page rendering tests for critical pages.
- Playwright smoke for signup, login, event creation, RSVP, deck
  declaration, pod generation, and game logging.
- Caddy config validation.
- systemd unit verification where practical.
- Backup and restore drill before production claims.

If a command cannot run, report why and what was verified instead.

---

## External Sources To Re-check

Use current primary sources before implementation work that depends on
external behavior:

- Rust release, edition, Cargo workspace, and rust-toolchain behavior.
- Leptos SSR, forms/actions, hydration, and Axum integration.
- Axum, tower, tower-http, tracing, cookies, sessions, and CSRF crates.
- sqlx migrations, compile-time query checking, offline mode, and
  PostgreSQL feature support.
- PostgreSQL version features, UUID generation, RLS, `pg_trgm`,
  `pg_stat_statements`, `btree_gin`, `pg_cron`, and `pgvector`.
- Scryfall bulk data format and API policy.
- Current Commander Brackets and Game Changers data.
- Caddy reverse proxy and TLS behavior.
- Cloudflare DNS/proxy behavior.
- Email provider sending requirements.

Trust current primary docs over this file.

---

## Recent Work

- 2026-05-13 - Replaced the initial idea document with durable
  `README.md`, `BUILD.md`, and `AGENTS.md`; set the stack direction to
  Go, PostgreSQL, server-rendered HTML, HTMX, Caddy, systemd, and
  non-Docker PostgreSQL.
- 2026-05-13 - Added the Go web and worker skeleton, local HTMX/plain CSS
  frontend foundation, local PostgreSQL migration workflow, sqlc typed
  SQL generation, pgx database package, identity/session schema, and
  bcrypt password hashing.
- 2026-05-13 - Added signup, login, logout, settings, HttpOnly SameSite
  session cookies, CSRF-protected forms, playgroup schema and creation
  flow, role helpers, authenticated dashboard, and focused auth/playgroup
  handler tests.
- 2026-05-13 - Added Ubuntu self-hosting assets for the Go stack: Caddy
  site config, systemd units, production env template, deploy script with
  migration step, backup/restore scripts, and `docs/operations.md`.
- 2026-05-13 - Deployed the Go stack on the Ubuntu VM at
  `https://pod-tracker.app/`: installed release
  `/opt/pod-tracker/releases/20260513T210200Z`, migrated production
  PostgreSQL to goose version 3, replaced the Rails Puma unit with the Go
  web service on `127.0.0.1:8083`, started the Go worker, and updated the
  backup timer to use the `pg_dump` script.
- 2026-05-14 - Completed the remaining Phase 4 event privacy surface:
  location and host address visibility capture, member-scoped event
  access, public-safe event pages, invite-token guest RSVP flow,
  authenticated iCalendar feed, and focused tests for address visibility
  and guest scoping. Added readiness checks for migrations, jobs, and
  email tables.
- 2026-05-17 - Reoriented the active plan from Go to Rust, Leptos, Axum,
  Tokio, sqlx, and PostgreSQL while preserving the existing product scope
  and treating the Go app as parity reference behavior for the rewrite.
- 2026-05-17 - Added the Rust workspace foundation with Rust 1.95,
  workspace-managed dependencies, `pod-core`, `pod-db`, `pod-web`, and
  `pod-worker`; added an Axum/Tokio web binary, environment config,
  tracing, request IDs, panic logging, `/healthz`, `/readyz`, Leptos SSR
  base pages, static CSS, Rust `just` targets, and Rust CI checks.
- 2026-05-17 - Added SQLx-owned forward migrations for the Rust rewrite,
  PostgreSQL-backed CI query checks, typed `pod-db` health and
  identity/session repositories, configurable pool setup, and a SQLx
  migration smoke recipe.
- 2026-05-17 - Ported Rust identity and session auth surface: completed
  account and auth identity schema, added Argon2id password hashing,
  session token hashing, secure SameSite session cookies, CSRF-protected
  signup/login/logout forms, settings, authenticated dashboard access, and
  focused repository and route tests.
- 2026-05-17 - Ported Rust playgroup repository and route surface:
  playgroups, owner memberships, invites, settings, house rules, role
  permission helpers, authenticated playgroup listing/detail pages, scoped
  playgroup access tests, explicit event/reminder table migration checks,
  and readiness checks for migrations, jobs, and email tables.
- 2026-05-17 - Ported the Rust Phase 4 event surface before deployment
  cutover: event creation/edit routes, host address visibility rules,
  member and guest RSVP states with timing/travel details, public-safe
  event pages, invite-token RSVP flow, authenticated calendar feed, and
  focused tests for address privacy, guest scoping, and calendar
  authorization.
- 2026-05-17 - Ported the Rust reminder and email job skeleton: added
  typed event reminder inserts, `ops.email_deliveries` and
  `ops.background_jobs` repository coverage, `send_email` worker job
  claiming with `FOR UPDATE SKIP LOCKED`, SMTP2GO delivery status updates,
  retry handling, and focused PostgreSQL tests.
- 2026-05-17 - Added the Rust deployment release path: introduced the
  `pod-tracker-migrate` SQLx migration binary, wired `just release`,
  converted the deploy script to Cargo release builds and SQLx
  migrations, updated the production environment template and operations
  runbook, verified release binaries, smoked `/healthz` and `/readyz`
  locally, and completed a local backup/restore drill.
- 2026-05-17 - Completed local Rust deployment config checks: documented
  the stable Caddy proxy port and rollback path, verified Rust web and
  worker systemd unit paths, added `just caddy-validate` and
  `just systemd-verify`, and added Rust-side security headers with route
  tests.
- 2026-05-17 - Added `docs/privacy.md` covering sensitive fields,
  membership and guest scopes, address visibility, calendar privacy,
  logging boundaries, database authorization expectations, and
  backup/restore handling without overstating unimplemented guarantees.
- 2026-05-18 - Completed the Rust Phase 6 deck registry slice: added deck
  and event declaration migrations, deck domain validation, SQLx
  repository access with ownership and visibility checks, SSR deck
  registry/search/detail pages, event deck declaration UI, and focused
  repository, route, and browser smoke coverage.
- 2026-05-18 - Completed the Rust Phase 7 pod generation slice: added pod
  and seat migrations, pod state/domain scoring helpers, SQL-backed
  confirmed-attendee generation, scored repository output, admin pod
  route controls for generation, locks, manual seat moves, publish, email
  notification jobs, SQL Observatory pod query entries, and focused
  repository and route tests for generation, locks, movement, publishing,
  and permissions.
