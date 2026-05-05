# BUILD.md

Active build manual for Ideal Magic. Reading this plus `AGENTS.md` and `README.md` is enough context to ship.

Last updated: 2026-05-05 (Slice 2 first pass — pods of user decks, share links)

## How agents work this file

This is a single-developer build of a Commander companion app, not a corporate roadmap. Reading and shipping against this file should both be fast.

- **Ship vertical slices that move the user-visible product forward.** Each pass should deliver a concrete capability someone can demo at a kitchen table, not horizontal plumbing.
- **Skip ahead when it pays.** Pick the slice that delivers the most user-visible value next, regardless of order. The slice list below is roughly value-ordered, not gospel.
- **2–4 related checkboxes per pass minimum.** Bigger is fine when boxes share infrastructure. One-box passes are okay only when the work is genuinely isolated; flag the reason in the commit.
- **Trim ceremony.** When a slice ships, check only the boxes that shipped, append one line to "Recent slices," and update "What's live now" only if a user-visible capability changed. Do not write a paragraph per pass.
- **The verify gate is `bin/verify`.** Run it once before each commit, not per checkbox.
- **A box is `[x]` only if it shipped, was tested, and is in `main`.** `[~]` means partial. `[ ]` means open. Never check a box for aspirational work.
- **If a slice is larger than expected, ship the part that's done and tested, leave the rest open.** Honesty beats progress theater.
- **Hard constraints (next section) don't move.** Everything else in this file is editable as you learn — delete or rewrite boxes that turn out wrong-shaped, premature, or redundant with how the code actually evolved. This is a living plan, not a fossil.

## Hard constraints

These don't move:

- Card facts and Commander legality come from deterministic source data (Scryfall + mtgcommander.net rules/banlist). AI interprets, never rules.
- Public deck URLs, pasted decklists, and uploaded text exports are the supported import paths. No scraping authenticated provider data.
- AI uses Codex App Server account-auth (ChatGPT browser OAuth or device-code). No generic OpenAI API OAuth, no ChatGPT password collection, no browser-visible API keys, no scraping ChatGPT.
- Codex credentials are per-user, encrypted at rest, never logged, never rendered to a browser.
- Salt and social-friction scores are conversation aids, not moral judgments. Evidence-backed, neutral language.
- Mobile-first. The site has to be usable on a phone in a noisy game store at 9 PM.
- Self-hostable. No hard dependency on external PaaS for the runtime path.
- WotC Fan Content Policy applies. Card names/text/art use the unofficial disclaimer; nothing is paywalled without legal review.

## Stack

- Ruby 4.0.3 / Rails 8.1.3 monolith on PostgreSQL 17.
- Hotwire (Turbo + Stimulus), Tailwind CSS v4, ViewComponent, Propshaft.
- Solid Queue / Cache / Cable in-Puma.
- Native Puma under systemd behind Caddy. PostgreSQL on the host. No Docker Compose.
- Minitest. Brakeman + RuboCop + ERB lint + bundler-audit + importmap audit gated through `bin/verify`.

## What's live now

- **Auth & accounts:** signup, sign-in, password reset, email verification, account settings (display name, timezone, units), account deletion, JSON account export, audit events.
- **Codex account-auth:** encrypted credential storage, browser/device-code login UX, refresh-status, remote sign-out, per-user/global quota policy with rate-limit display. Transport boundary ships with a fail-closed `NullTransport` — no real Codex calls happen yet.
- **Provider link placeholders** for Archidekt and Moxfield public profile URLs (no third-party password collection).
- **Card corpus:** Scryfall bulk-data ingestion, Commander rules/banlist snapshot, internal tag taxonomy with curated salt/social-friction overrides, deterministic legality checker, daily Solid Queue refresh job.
- **Deck import:** pasted text, uploaded text file, public Archidekt URL, public Moxfield URL. Imports surface unparsed lines, source attribution, audit events.
- **Deterministic deck analysis:** every import runs feature extraction, Commander legality, and a six-axis scorecard (Power, Speed, Interaction, Consistency, Salt, Social Friction). Deck show page renders per-score evidence drawers, legality result, and a tuning recommendation list. AI evaluation is not wired up yet.
- **Pods (2–4 of the user's decks):** build a pod, get per-axis spread/average/outliers, archenemy/pubstomp/durdle warnings, a Rule 0 brief (power band, tempo, combo/stax notes, salt/friction notes), and per-deck swap suggestions. Mobile-readable and printable show page. Opt-in revocable public share link. Guest deck import (paste / public URL) is the next pass.
- **Seeded users:** admin (`stephenvsawyer@gmail.com`, password from `IDEAL_MAGIC_ADMIN_PASSWORD`) and demo (`demo@demo.com` / `demo1234`). `bin/rails demo:reset` factory-resets the demo account.
- **Production:** live at https://ideal-magic.com via Caddy + systemd + host PostgreSQL. `bin/redeploy` is the iteration loop.

## Slices

In rough value order. Each slice is one or two passes of work and ships a user-visible capability.

---

### Slice 1 — Deterministic deck analysis on the show page

The biggest gap right now: a user imports a deck and only sees a card list. Make it show an honest read. No AI yet — that's Slice 6.

- [x] Compute and persist a feature vector per deck: counts for ramp, fast mana, draw, tutors, interaction, wipes, protection, lands, mana sources, recursion, win-condition markers, plus mana curve and color requirements. Use the existing tag taxonomy.
- [x] Run deterministic Commander legality on every import and store the result against the deck.
- [x] Estimate power, speed, interaction, and consistency from feature bands. Each gets a 1–10 value plus a short evidence list (the cards/tags that drove it).
- [x] Compute deterministic salt score and social-friction score from salt/friction-tagged cards, fast mana, mass land denial, extra turns, theft, chaos, repetitive locks, stax, and combo compactness. Neutral labels.
- [x] Render a deck show page surfacing all six scores, an evidence drawer per score, the legality result, and a recommendation list (mana, draw, ramp, interaction, salt-reduction).
- [x] Re-compute scores when a deck's cards change. Synchronous on save is fine — no background job needed yet.
- [x] Add benchmark deck fixtures spanning precon / casual / upgraded / high-power so the score bands are reviewable.
- [x] Tests: feature extraction unit, scoring against benchmark fixtures, system test that imports a deck and asserts evidence-backed scores render.

### Slice 2 — Pods (2–4 deck comparison and Rule 0 brief)

- [x] Pod model: pod, pod slot, pod analysis run, plus a shareable-link token.
- [~] Build a pod from 2–4 of the user's decks. Allow a guest deck via paste or public URL. (User-deck pods ship; guest deck via paste/URL pending.)
- [x] Pod analysis: per-axis spread, average, outliers, archenemy/pubstomp/durdle warnings, salt and social-friction spread.
- [x] Rule 0 brief: power band, speed expectations, combo/stax notes, salt/friction notes, suggested swaps.
- [x] Pod show page that's mobile-readable and printable.
- [x] Public pod share link, opt-in, revocable.
- [x] Tests: pod service tests across balanced and mismatched fixtures; system test for create → analyze → share.

### Slice 3 — Game-night sessions and result recording

- [ ] Session model: session, player, session_player, session_deck, pod_seat, pod_result. Players are user-owned named entities — no public ranking surface.
- [ ] Create a session (date, location, notes) and check players in with their deck of the night.
- [ ] Suggest pod seating from checked-in players; allow manual overrides.
- [ ] Record results: winner, draw state, turns, win condition, free-text notes.
- [ ] Snapshot the deck revision and analysis used for each pod seat so meta history is honest later.
- [ ] Session summary page with the night's pods, results, and links back to deck/analysis snapshots.
- [ ] Tests: session workflow system test from create → check-in → seat → record → summary.

### Slice 4 — Collection and ownership

- [ ] Collection model: collection_card, collection_import, unresolved_entry.
- [ ] Pasted and uploaded collection import (text + simple CSV).
- [ ] Manual add / edit / remove / quantity adjust.
- [ ] Unresolved-card review for ambiguous names.
- [ ] Owned vs missing per deck on the deck show page.
- [ ] Demand pressure: which missing cards matter across multiple decks.
- [ ] Recommendations distinguish "you already own this" from "you'd have to buy it." No price/marketplace flow.
- [ ] Tests: import parser, ownership service, system test for collection → deck gaps.

### Slice 5 — Matchup journal and meta trends

- [ ] Matchup note model: belongs to user, links to deck, commander, opponent (player), pod, session. Tags + free text.
- [ ] Note CRUD with search by tag, deck, commander, player, pod, session.
- [ ] Pre-game context surface: when seating a pod, show prior notes for those decks/commanders/opponents.
- [ ] Post-game prompt for wins/losses/draws/short games/dead draws/missing cards.
- [ ] Deck performance: games, wins, draws, win rate with sample-size confidence, average turns, last played.
- [ ] Commander meta: appearances, wins, win rate, recent trend. Sample size visible; never pretend thin data is certain.
- [ ] Revision performance: connect deck revisions to results so "what changed since this deck last won" is answerable.
- [ ] Tests: matchup search, meta service against fixture sessions.

### Slice 6 — Codex AI evaluation as augmentation

The v1 differentiator. Build it on top of deterministic analysis, not as a replacement.

- [ ] Implement a real Codex App Server JSON-RPC transport against the documented account-auth surface. Replace `NullTransport` with the live client behind a feature flag.
- [ ] JSON schema for AI scorecards: power/speed/interaction/consistency/salt/social-friction adjustments, friction drivers, Rule 0 talking points. Cite deterministic facts; mark uncertainty.
- [ ] Single-deck prompt v1: pass the deterministic feature vector, decklist, commander, combo candidates, salt/friction evidence, and rubric. Ask for adjustments + explanations, not raw scores.
- [ ] Pod prompt v1: same shape, pod-aware.
- [ ] Background job that runs evaluation against a quota-checked Codex account; surfaces queued / running / failed / stale states on the deck and pod pages.
- [ ] Replayable runs: store prompt version, model, inputs, outputs, latency, and rate-limit snapshot per `AnalysisRun`.
- [ ] Recorded-fixture tests for the prompt → response → schema validation path. No live calls in CI.
- [ ] AI explanations render alongside deterministic evidence; the deterministic numbers stay visible.

### Slice 7 — PWA and table-side polish

- [ ] Web app manifest, service worker, app-shell cache.
- [ ] Recent decks and analyses cached for read-only offline access.
- [ ] iOS home-screen + Android maskable icon coverage.
- [ ] Cache versioning and an update prompt that doesn't trap users on stale assets.
- [ ] Mobile bottom nav, desktop sidebar nav, responsive deck-list controls (search, tag filter, role filter).
- [ ] Honest offline states: never pretend AI runs, imports, or new results have reached the server while offline.

### Slice 8 — Exports, share links, and operational polish

- [ ] Deck export to plain text, CSV, and JSON from the deck show page.
- [ ] Analysis export to Markdown and JSON.
- [ ] Public deck and analysis share links with opt-in revocation; safe defaults (no playgroup notes leak).
- [ ] Extend account export to cover collection, sessions, and matchup notes once those slices land.
- [ ] PostgreSQL `pg_dump` backup script + scheduled timer + a documented restore drill.
- [ ] Operator runbook for the daily Scryfall corpus refresh job.

---

## Recent slices

Newest first. One line per shipped tranche.

- 2026-05-05 — Slice 2 first pass: pods of the user's existing decks. `Pod`, `PodSlot`, `PodAnalysisRun`, share-token surface, `Pods::Analyzer` (spread, average, outliers, archenemy/pubstomp/durdle/salt/friction warnings), `Pods::RuleZeroBrief`, `Pods::SuggestionsBuilder`, mobile + print pod show page, opt-in revocable `/p/:token` public share. Guest-deck slot via paste / public URL deferred.
- 2026-05-05 — Slice 1 closed: precon (Korlash) and high-power (Najeela 5C) benchmark fixtures plus a `Decks::BenchmarkScoringTest` that asserts power, salt, friction, tutor, fast-mana, stax, and combo counts grow across the precon → casual → upgraded → high-power band.
- 2026-05-05 — Slice 1 first pass: deterministic feature extractor, six-axis scorer, legality-gated `Decks::Analyzer`, deck-show evidence drawers, and importer hook. Benchmark-fixture pass and score-band calibration still open.
- 2026-05-04 — BUILD.md rewritten as user-visible slices; phase-by-phase plan retired.
- 2026-05-04 — Seeded admin + demo accounts and `bin/rails demo:reset` rake task for factory-resetting the demo user.
- 2026-05-04 — Public Moxfield deck URL import (`Decks::MoxfieldClient` + `Decks::Adapters::Moxfield`).
- 2026-05-04 — Public Archidekt deck URL import (`Decks::ArchidektClient` + `Decks::Adapters::Archidekt`).
- 2026-05-04 — Text-file decklist upload import (`Decks::Adapters::TextFile`).
- 2026-05-04 — Pasted decklist import end to end (`Decks::Importer` + `DecksController`).
- 2026-05-04 — Codex account-auth UX: browser/device-code login, refresh-status, remote sign-out, quota policy with rate-limit display.
- 2026-05-04 — Codex App Server account-auth service layer + encrypted credential storage.
- 2026-05-04 — Account settings, email verification, account deletion, JSON account export.
- 2026-05-04 — Email/password registration and signed-in dashboard.
- 2026-05-04 — Card corpus: Scryfall ingestion, Commander legality engine, tag taxonomy with curated salt/friction overrides, daily refresh job.
- 2026-05-04 — Domain models for decks, deck cards, commanders, provider links, card sets, oracle cards, printings, rulings, legality snapshots, analysis runs, scorecards, pod evaluations, audit events.
- 2026-05-04 — Production deployment live at https://ideal-magic.com (Caddy + systemd + host PostgreSQL + `bin/redeploy`).
- 2026-05-03 — Rails foundation scaffolded with the target stack and quality gates.

## Human-only work (parked)

Not agent tasks. They depend on real beta usage and real games:

- Calibrate score bands against actual precon / casual / upgraded / high-power / cEDH decks once Slice 1 ships and Stephen + a small group can play with it.
- Tune the salt/social-friction taxonomy from observed playgroup feedback.
- Run a closed beta of pod evaluation and session recording with Stephen's actual playgroup before declaring v1.
- Decide whether passkeys/WebAuthn lands before or after v1 based on how often password-only auth becomes friction.

If real-world feedback changes the engineering picture, fold the result into a slice above and check the affected boxes there.

## External truth to re-check before scaffolding integrations

- Scryfall asks for <10 req/s and bulk data for large workloads.
- Commander rules + banlist live at mtgcommander.net. Latest official update visible on 2026-05-04 was the 2024-09-23 quarterly update.
- Codex App Server account-auth endpoints at https://developers.openai.com/codex/app-server are the supported surface for v1 AI.
- Archidekt has a publicly observable API for public decks but no formal docs — adapter may break.
- Moxfield has public deck pages and a public API (`api2.moxfield.com/v3/decks/all/<slug>`) but no formal docs — same caveat.

Re-check versions and endpoints when starting a new integration; trust the latest source over this file.
