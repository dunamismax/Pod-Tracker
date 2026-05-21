# Advanced Intelligence Boundaries

Pod Tracker's recommendation features are SQL-scoped and heuristic by
default. They should stay useful without pgvector, external AI services,
or unrestricted natural-language SQL generation.

## Current Recommendation Types

- Pod generation uses SQL-backed candidate data plus deterministic scoring
  and a bounded optimizer.
- Similar deck recommendations use visible latest decklists, commander,
  archetype, bracket, color identity, and tags.
- Collection-aware deck suggestions use only collections and decks visible
  to the requesting user, then return aggregate coverage and reason labels.

These paths are not semantic or AI-backed. They must keep working on a
plain PostgreSQL install with the required extensions listed in
`BUILD.md`.

## Optional pgvector Research

`pgvector` can be useful later for semantic card and deck search, but it
must remain optional:

- Do not add `create extension vector` to default migrations.
- Gate vector schema, indexes, jobs, and queries behind an explicit local
  setup path or separate optional migration.
- Preserve SQL and heuristic recommendation behavior as the default and
  test the app without pgvector.
- Keep embeddings local or document every external provider boundary
  before any network-backed embedding job exists.
- Never embed private notes, invite tokens, host addresses, emails, phone
  numbers, production logs, or database dumps.

A safe first implementation would add a separate optional migration for
card/deck embedding tables, repository methods that return empty/disabled
results when the vector extension is unavailable, and tests that run the
normal workspace gate against a database without pgvector.

## Natural-Language Meta Query Research

Unrestricted natural-language-to-SQL is risky for this product because the
database contains host addresses, RSVP details, notes, invite tokens,
calendar scope, and other sensitive playgroup data. A generated query can
also bypass carefully scoped repository methods if it is allowed to run
against raw tables.

The safe direction is a constrained SQL Observatory extension rather than
open-ended NL-to-SQL:

- Map plain-language prompts to a fixed catalog of approved observatory
  queries.
- Require each query to declare viewer scope, inputs, safe output columns,
  redacted sample data, and expected indexes.
- Execute through existing repository/service methods or security-barrier
  views, not arbitrary model-generated SQL.
- Refuse prompts that request private addresses, contact details, invite
  tokens, raw notes, logs, backups, or cross-playgroup data.
- Log only query ids, route family, request id, and high-level refusal
  reasons.

This keeps meta exploration inspectable and PostgreSQL-first while
preserving the privacy boundaries documented in `docs/privacy.md`.
