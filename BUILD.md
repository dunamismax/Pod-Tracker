# BUILD.md

Active build plan for Pod Tracker. `README.md` introduces the product.
This file tracks stack choices, PostgreSQL design, phases, and
verification while the app is built.

Treat unchecked boxes as plan. Move stable material into `docs/`,
`README.md`, or runbooks as the implementation matures.

---

## What's Live Now

- Repository exists with GPL-3.0 license.
- `origin` fetches from GitHub and pushes to GitHub plus Codeberg.
- Public production domain is [https://pod-tracker.app/](https://pod-tracker.app/).
- The old idea document has been distilled into `README.md`,
  `BUILD.md`, and `AGENTS.md`.
- Go web and worker skeleton exists with local HTMX/plain CSS,
  PostgreSQL migrations, sqlc typed queries, identity/session schema,
  signup/login/logout, CSRF-protected forms, and basic playgroups.

---

## Stack Decisions

- **Go** for the application and worker binaries.
- **PostgreSQL** as the system of record and main product engine.
- **Server-rendered HTML** for primary screens.
- **HTMX** for partial updates and interaction.
- **Tailwind CSS or restrained plain CSS**; choose once the first layout
  exists.
- **SSE** for browser event streams.
- **PostgreSQL `LISTEN` / `NOTIFY`** for lightweight realtime fanout.
- **sqlc** preferred for typed SQL; use an equivalent only if it clearly
  fits the repo better.
- **Goose, tern, or golang-migrate** for forward-only migrations; choose
  one in Phase 1 and keep it canonical.
- **PostgreSQL-backed job tables** using `FOR UPDATE SKIP LOCKED` for
  imports, reminders, exports, and materialized-view refreshes.
- **Caddy + systemd + Ubuntu VM** for production.
- **No Docker PostgreSQL.** Local development uses the installed macOS
  PostgreSQL service. Production uses a real PostgreSQL service on the
  Ubuntu VM.

Current local baseline observed on 2026-05-13:

```text
Go: go1.26.3 darwin/arm64
PostgreSQL: 18 Homebrew
psql: /opt/homebrew/opt/postgresql@18/bin/psql
```

The skeleton uses PostgreSQL 18.

---

## Product Invariants

- Game night planning is the center of the product.
- Deckbuilding supports event planning; it does not dominate the MVP.
- PostgreSQL is the source of truth for state, permissions, analytics,
  search, jobs, and history.
- Host addresses are sensitive and never globally visible.
- Guests see only the event scope they were invited into.
- Public pages use tokenized, public-safe views.
- Competitive rankings are optional; default analytics emphasize meta
  health, variety, and planning.
- Scryfall raw payloads are stored in JSONB alongside normalized fields.
- Commander Brackets and Game Changers are versioned data, not hard-coded
  eternal constants.
- Do not start with AI, pgvector, paid billing, native mobile apps, or a
  full Moxfield replacement.

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

Use `vector` only after the core product works. Use PostGIS only when
distance, map, or traffic-aware leave-time features earn it.

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
- Use UUID primary keys with time-ordered UUIDs where practical.
- Add database constraints for invariants the database can enforce.
- Prefer check constraints or lookup tables over unchecked strings.
- Use RLS or public-safe views for tenant and guest boundaries.
- Keep raw Scryfall JSONB payloads, but normalize the columns needed for
  search, filtering, legality, and analytics.
- Materialized views should power expensive dashboard and pairing
  summaries.
- Test migrations against a real PostgreSQL database.

---

## Target Source Layout

```text
cmd/
  pod-tracker-web/
  pod-tracker-worker/
internal/
  app/
  auth/
  config/
  db/
  http/
  playgroups/
  events/
  decks/
  pods/
  games/
  mtg/
  meta/
  reminders/
  search/
  audit/
web/
  templates/
  static/
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

State-changing actions should be form posts or HTMX posts with CSRF
protection and clear authorization checks.

---

## Phases

Ordered intent, not rigid sequence. Each phase should leave the repo in a
state where documented verification passes on a clean checkout.

### Phase 0 - Project Foundation

- [x] Read and replace the original idea document with durable docs.
- [x] Write `README.md` with live URL and product positioning.
- [x] Write this `BUILD.md` as the active build checklist.
- [x] Write repo-local `AGENTS.md`.
- [x] Add `.gitignore` for Go, local env files, logs, build outputs,
      database dumps, IDE files, and OS files.
- [x] Add `.editorconfig`.
- [x] Add top-level `justfile`.
- [x] Add `.env.example` without secrets.
- [x] Add CI placeholder for docs, Go, SQL, and frontend checks.
- [x] Confirm or normalize dual-push GitHub and Codeberg remote setup.

### Phase 1 - Go Web Skeleton

- [x] Create Go module.
- [x] Add `cmd/pod-tracker-web` HTTP server.
- [x] Add `cmd/pod-tracker-worker` placeholder.
- [x] Add config loading from environment.
- [x] Add structured logging and request IDs.
- [x] Add `/healthz` and `/readyz`.
- [x] Add server-rendered base layout.
- [x] Add HTMX as a pinned local static asset or locked dependency.
- [x] Add CSS pipeline decision and first compiled stylesheet.
- [x] Add public home page at `/`.
- [x] Add `just run`, `just worker`, `just fmt`, `just check`,
      `just test`.

### Phase 2 - Local PostgreSQL And Migrations

- [x] Document local Homebrew PostgreSQL setup in `docs/development.md`.
- [x] Add database creation and reset commands.
- [x] Choose and wire the migration tool.
- [x] Add `001_extensions.sql` for required extensions.
- [x] Add database connection pool.
- [x] Add migration smoke test against local or ephemeral PostgreSQL.
- [x] Add typed SQL generation with sqlc or chosen equivalent.
- [x] Add initial database package and transaction helper.

### Phase 3 - Identity, Sessions, And Playgroups

- [x] Add users and sessions schema.
- [x] Add secure password hashing.
- [x] Add signup, login, logout, and settings.
- [x] Add secure, HttpOnly, same-site session cookies.
- [x] Add CSRF protection for state-changing forms.
- [x] Add playgroups, memberships, invites, roles, settings, and house
      rules.
- [x] Add owner/admin/member/host/guest/viewer role checks.
- [x] Add basic authenticated dashboard.
- [x] Add tests for auth, sessions, and playgroup access.

### Phase 4 - Events, Hosts, RSVPs, And Calendar

- [x] Add event, host, location, RSVP, guest, and reminder tables.
- [x] Add event creation and edit flow.
- [x] Add host address visibility rules.
- [x] Add RSVP states: yes, maybe, no, waitlist.
- [x] Capture arrival time, leaving time, guest count, travel buffer, and notes.
- [x] Add public-safe event page and invite-token RSVP flow.
- [x] Add iCalendar export/feed per user.
- [x] Add reminder job skeleton and email delivery log.
- [x] Add tests proving address visibility and guest scoping.

### Phase 5 - Deck Registry And Event Declarations

- [ ] Add deck registry with commander, color identity, claimed bracket,
      archetype, tags, visibility, active/retired state, and notes.
- [ ] Add deck metadata flags: Game Changers count, infinite combo,
      fast mana, tutors density, extra turns, mass land denial, and salt
      notes.
- [ ] Add deck visibility: private, playgroup, public.
- [ ] Add event deck declarations with preference and testing notes.
- [ ] Add basic deck search.
- [ ] Add tests for deck ownership, visibility, and declarations.

### Phase 6 - Pod Generation

- [ ] Add pod and pod seat tables.
- [ ] Add pod states: proposed, locked, active, completed, cancelled.
- [ ] Add SQL-backed candidate generation for confirmed attendees.
- [ ] Score pod size fit, bracket compatibility, repeated player pairs,
      repeated deck matchups, guest placement, and availability windows.
- [ ] Allow admin manual edits and manual locks.
- [ ] Publish pod assignments and notify players.
- [ ] Add SQL Observatory entry for the pod candidate and scoring query.
- [ ] Add tests covering generation, constraints, locks, and permissions.

### Phase 7 - Game Logging

- [ ] Add games, game players, results, notes, and event completion.
- [ ] Support result types: normal win, combo win, combat win,
      concession, draw, time called, unfinished, archenemy win, team win.
- [ ] Capture winner, turn count, duration, first player, elimination
      order, tags, and notes where provided.
- [ ] Keep logging fast enough to use between games.
- [ ] Update matchup history after each logged game.
- [ ] Add tests for game logging and event history.

### Phase 8 - Scryfall Import And Card Search

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

### Phase 9 - Decklist Import, Export, And Bracket Checks

- [ ] Add plain-text decklist paste/import.
- [ ] Match card names through exact, normalized, and fuzzy lookup.
- [ ] Detect commander(s) and color identity.
- [ ] Add Game Changers version tables.
- [ ] Count Game Changers per deck version.
- [ ] Show bracket-relevant warnings.
- [ ] Export plain-text, Moxfield-compatible, and Archidekt-compatible
      lists.
- [ ] Snapshot deck bracket analysis over time.
- [ ] Add tests for parsing, matching, warnings, and exports.

### Phase 10 - Meta Dashboard

- [ ] Add materialized views for attendance, deck win rates, player win
      rates, commander popularity, bracket distribution, color identity,
      archetypes, matchup history, and stale decks.
- [ ] Add dashboard focused on meta health, variety, and planning.
- [ ] Make competitive ranking optional rather than the default lens.
- [ ] Refresh materialized views through background jobs.
- [ ] Add SQL Observatory entries for the dashboard views.
- [ ] Add tests for metrics and refresh behavior.

### Phase 11 - Collection Tracking

- [ ] Add collections and collection card quantities.
- [ ] Track printing, foil flag, condition, and location when provided.
- [ ] Show missing cards by deck.
- [ ] Generate proxy/print lists.
- [ ] Add wishlists.
- [ ] Add collection visibility and ownership checks.
- [ ] Add tests for collection calculations and privacy.

### Phase 12 - SQL Observatory

- [ ] Build `/observatory`.
- [ ] Show real SQL for pod generation, avoid-repeat pairing, bracket
      compatibility, fuzzy card search, Game Changers count, reminders,
      matchup history, and Scryfall JSONB exploration.
- [ ] Explain inputs, indexes, query plan shape, and output.
- [ ] Add safe sample data or scrubbed fixtures.
- [ ] Never expose private addresses, emails, phone numbers, or tokens.

### Phase 13 - Operations And Deployment

- [x] Add Caddy config for `pod-tracker.app`.
- [x] Add systemd units for web and worker binaries.
- [x] Add deployment script for the Ubuntu VM.
- [x] Add production environment template without secrets.
- [x] Add database migration step for deploy.
- [x] Add `pg_dump` backup script.
- [x] Add restore script and restore drill documentation.
- [x] Add operations runbook in `docs/operations.md`.
- [x] Add readiness checks for DB, migrations, jobs, and email.

### Phase 14 - Hardening

- [ ] Add rate limits for signup, login, RSVP, invites, deck import,
      search, and admin actions.
- [ ] Add audit events for auth, membership, invite, event, RSVP, pod,
      address reveal, and result changes.
- [ ] Add structured error pages.
- [ ] Add log redaction checks.
- [ ] Add CSRF tests.
- [ ] Add security header checks.
- [ ] Add privacy model in `docs/privacy.md`.
- [ ] Add backup and restore drill from a real snapshot before public
      claims.

### Phase 15 - Advanced Intelligence

- [ ] Improve pod scoring with matchup freshness and deck variety.
- [ ] Add similar deck recommendations.
- [ ] Add collection-aware deck suggestions.
- [ ] Add optional pgvector semantic card/deck search.
- [ ] Add natural-language meta query research after SQL Observatory is
      useful.
- [ ] Document which recommendations are SQL, heuristic, semantic, or
      AI-backed.

---

## Verification

Narrowest useful command first, then broaden.

Docs-only work:

```sh
git diff --check
```

Once the skeleton exists:

```sh
just fmt
just check
just test
```

Expected checks as the app matures:

- Go formatting and tests.
- Migration validation against real PostgreSQL.
- sqlc generation check.
- Server startup smoke.
- `/healthz` and `/readyz`.
- HTML/template rendering tests for critical pages.
- Playwright smoke for signup, login, event creation, RSVP, pod
  generation, and game logging.
- Caddy config validation.
- systemd unit verification where practical.
- Backup and restore drill before production claims.

If a command cannot run, report why and what was verified instead.

---

## External Sources To Re-check

Use current primary sources before implementation work that depends on
external behavior:

- Go release and module behavior.
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
- 2026-05-13 - Added signup, login, logout, settings, HttpOnly
  SameSite session cookies, CSRF-protected forms, playgroup schema and
  creation flow, role helpers, authenticated dashboard, and focused
  auth/playgroup handler tests.
- 2026-05-13 - Added Ubuntu self-hosting assets for the Go stack:
  Caddy site config, systemd units, production env template, deploy
  script with migration step, backup/restore scripts, and
  `docs/operations.md`.
- 2026-05-13 - Deployed the Go stack on the Ubuntu VM at
  `https://pod-tracker.app/`: installed release
  `/opt/pod-tracker/releases/20260513T210200Z`, migrated production
  PostgreSQL to goose version 3, replaced the Rails Puma unit with the
  Go web service on `127.0.0.1:8083`, started the Go worker, and updated
  the backup timer to use the new `pg_dump` script.
- 2026-05-14 - Completed the remaining Phase 4 event privacy surface:
  location and host address visibility capture, member-scoped event
  access, public-safe event pages, invite-token guest RSVP flow,
  authenticated iCalendar feed, and focused tests for address visibility
  and guest scoping. Added readiness checks for migrations, jobs, and
  email tables.
