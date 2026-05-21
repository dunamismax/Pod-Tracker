# Pod Tracker

**Live self-hosted URL:** [https://pod-tracker.app/](https://pod-tracker.app/)

Pod Tracker is a self-hosted Commander playgroup operating system for
planning game nights, collecting RSVPs, forming fair pods, tracking
decks, logging games, and understanding a playgroup's evolving meta.

The point is not to build another deckbuilder. The point is to build the
best PostgreSQL-first Commander night planner on the internet.

## Product Thesis

Commander groups do not only need deck tools. They need one place to
answer:

- Who is playing this week?
- Where and when are we meeting?
- Who is hosting, and who can see the address?
- What decks are people bringing?
- Which pods are fair tonight?
- Which players and decks have not seen each other lately?
- What happened last time?
- What does the group meta look like over time?

Pod Tracker is built around the game-night loop:

1. Create a playgroup.
2. Schedule an event.
3. Invite players.
4. Collect RSVPs and deck declarations.
5. Generate and adjust pods.
6. Log games.
7. Refresh the meta dashboard.

## Stack

- **Rust** application monolith.
- **Axum** for HTTP routing, middleware, and server edges.
- **Leptos** for server-rendered application UI and focused hydrated
  interactions where they earn their place.
- **Tokio** for async runtime.
- **PostgreSQL** as the source of truth.
- **Server-rendered HTML** for the core product.
- **Restrained plain CSS** by default; add a heavier styling pipeline only
  when the product proves it needs one.
- **SSE** and PostgreSQL `LISTEN` / `NOTIFY` for lightweight realtime.
- **sqlx or equivalent Rust typed SQL workflow** for explicit database
  access.
- **No Docker PostgreSQL** for local development or production.

Local development uses the installed macOS PostgreSQL service. At project
start, this machine has Homebrew PostgreSQL 18 available at
`/opt/homebrew/opt/postgresql@18`.

Production target:

```text
Cloudflare DNS
  -> Ubuntu VM
  -> Caddy
  -> pod-tracker-web
  -> pod-tracker-worker
  -> PostgreSQL service
```

The existing Go implementation is historical reference behavior. New
product work proceeds through the live Rust/Leptos/Axum application in
[BUILD.md](BUILD.md), with PostgreSQL remaining the visible engine of the
product.

## PostgreSQL Showcase

Pod Tracker should make PostgreSQL visible as the engine of the product,
not an interchangeable persistence layer.

Core PostgreSQL features to demonstrate:

- Relational modeling for players, playgroups, events, RSVPs, decks,
  pods, games, cards, and collection data.
- `pg_trgm` fuzzy search for card, commander, deck, and player lookup.
- Full-text search over cards, house rules, deck notes, and game logs.
- JSONB for raw Scryfall payloads and flexible event/deck metadata.
- Materialized views for meta dashboards and pairing history summaries.
- Background job tables using `FOR UPDATE SKIP LOCKED`.
- `LISTEN` / `NOTIFY` for realtime UI events.
- Row-Level Security for playgroup, guest, event, and host-address
  boundaries.
- Optional local `pgvector` support for semantic card and deck search,
  kept outside the default migration path.

The signature demo feature is the **SQL Observatory**: a page that shows
the real SQL behind pod generation, pairing history, fuzzy card search,
Game Changers analysis, reminders, and materialized meta views.

## MVP

The MVP is usable when a real playgroup can plan and run a Commander
night from invitation to pod assignment to game results.

Minimum launch checklist:

- Login and sessions work.
- Playgroups and memberships work.
- Events can be created.
- Host locations and address privacy work.
- RSVPs work.
- Calendar export works.
- Reminder jobs work.
- Deck registry and event deck declarations work.
- Pods can be generated, manually edited, locked, and published.
- Games can be logged quickly.
- Basic meta dashboard exists.
- Scryfall import and card search work locally.
- Backup and restore are documented.
- Caddy/systemd deployment is documented.
- No secrets, local config, or database dumps are committed.

## Development Status

This repository now runs the PostgreSQL-first Rust application using Axum
and Leptos in production. See [BUILD.md](BUILD.md) for the active phase
checklist and [AGENTS.md](AGENTS.md) for repo-local operating rules.

## License

MIT. See [LICENSE](LICENSE).
