# BUILD.md

Last drafted: 2026-05-03
Last updated: 2026-05-04 (card tag taxonomy and curated overrides)

## Agent Operating Rules

Future agents working in `ideal-magic` must follow these rules before touching code or docs:

- Read `README.md` and this file first.
- Treat this file as the active build execution manual until the product is shipped and stable docs fully describe reality.
- Keep this file current whenever scope, sequencing, architecture decisions, or verified repo truth changes.
- Only check a box after the work is completed, committed in the repo, and verified by the listed checks.
- Do not mark a box done for intent, partial progress, generated code that was not run, or unverifiable claims.
- Keep `README.md` focused on current product truth. Keep future execution detail here.
- If code and docs disagree, code wins, then update the docs.
- If this file and an older planning note disagree, this file wins.
- Do not copy DeckCheck's UI, copy, internal scoring, or proprietary behavior. Ideal Magic may compete with and improve on the category, but it must have its own implementation and rubric.
- Do not use unofficial, undocumented, or scraped deck-provider APIs for private user data. Public deck URLs and user-provided exports are allowed; authenticated provider sync requires a documented provider surface or explicit approval.
- AI usage must follow OpenAI's documented Codex App Server account-auth surface. Do not implement generic OpenAI API OAuth, ChatGPT password collection, scraping, browser-visible API keys, or hand-rolled token refresh outside Codex's documented flow.

## Build Decision

`Ideal Magic` is a Ruby on Rails web application for Commander deck and pod evaluation.

It is now the single primary Magic project. The best durable product ideas from Scrybase are consolidated here: deck lab, collection ownership, game-night sessions, pod seating/results, matchup notes, meta analytics, and tuning recommendations from real playgroup history. Do not port Scrybase's old stack or migration plan; rebuild the product ideas inside Ideal Magic's Rails architecture.

The approved product direction:

- Ruby and Rails latest stable at scaffold time.
- Rails monolith first, not a separate SPA and API unless the product earns that split later.
- PostgreSQL as the durable application database.
- Ideal Magic owns decks, collection, pods, sessions, matchup journal, meta analytics, and analysis as one product surface.
- Hotwire, Turbo, Stimulus, Tailwind CSS, and componentized Rails views for the primary UI.
- Rails-native background jobs, caching, and realtime features first.
- Codex App Server for AI evaluation using Codex-managed ChatGPT browser OAuth or device-code login as the exclusive v1 user-facing model path.
- PWA-first mobile and desktop experience.
- Docker Compose, Caddy, and systemd for Stephen's self-hosted Ubuntu deployment at `ideal-magic.com`.

## Current Repo Truth

The repo now contains a verified Rails foundation scaffolded on 2026-05-03, the first Phase 2 domain model tranche completed on 2026-05-04, the first Scryfall card corpus ingestion and normalization tranches completed on 2026-05-04, source-controlled Commander rules and banlist snapshot storage completed on 2026-05-04, and a source-controlled internal card tag taxonomy with curated overrides for role, salt, and social-friction tags completed on 2026-05-04.

Shipped foundation:

- Ruby 4.0.3 is pinned in `.ruby-version`, `.mise.toml`, and the Docker base image.
- Rails 8.1.3 is pinned in `Gemfile.lock`.
- PostgreSQL is configured for development, test, and production.
- Hotwire, Turbo, Stimulus, Tailwind CSS v4, ViewComponent, Propshaft, Puma, Thruster, Solid Queue, Solid Cache, and Solid Cable are installed.
- Rails authentication generator output exists for users, sessions, and password reset.
- Domain models and migrations exist for decks, deck cards, commanders, provider links, card sets, oracle cards, card printings, rulings, legality snapshots, analysis runs, scorecards, pod evaluations, salt/social-friction evidence, audit events, and card corpus refresh metadata.
- Fixture-tested Scryfall bulk-data ingestion exists for the `default_cards` bulk file, including polite `User-Agent` and `Accept` headers, API request throttling, streaming top-level JSON array parsing, normalized single-face and multi-face card facts, and upserts for card sets, oracle cards, and card printings.
- Source-controlled Commander rules and banlist snapshot storage exists for the current `mtgcommander` Commander legality source, including normalized banned-name lookups, category bans, rules metadata, seed loading, and fixture-tested idempotent import.
- Source-controlled internal card tag taxonomy and curated overrides exist for role tags (ramp, fast mana, tutor, card draw, protection, removal, stack interaction, board wipe, stax, combo, graveyard use, land, win condition), salt drivers (fast mana, mass land denial, extra turns, chaos, theft, repetitive loop, stax lockpiece, compact combo), and social-friction patterns (combo opacity, long-game pressure, disclosure required, interaction asymmetry), with tag/assignment models, normalized card-name lookup, oracle-card backfill on save, idempotent JSON-driven importer, and seed loading wired into `bin/rails db:seed`.
- Lookup and history indexes exist for deck ownership, provider IDs and URLs, normalized card names, Scryfall oracle and printing IDs, analysis history, scorecard ownership, legality snapshots, and audit events.
- Minitest is the primary test framework.
- Brakeman, RuboCop, ERB linting, bundler-audit, importmap audit, and `bin/verify` are wired.
- `.env.example`, `/up`, `/ready`, and an authenticated dashboard root route exist.

No deck import, collection import, card data refresh jobs, full Commander legality engine, scoring engine, Codex evaluation pipeline, provider integration implementation, Docker Compose runtime, deployment files, pod comparison workflow, game-night sessions, matchup journal, meta analytics, PWA offline behavior, or production configuration exists yet.

GitHub repository visibility was verified as public on 2026-05-03 through `gh repo view dunamismax/ideal-magic`. No license file exists; licensing is explicitly pending.

## Current External Truth To Preserve

These references were checked while drafting this plan. Agents must re-check current versions before scaffolding or implementing external integrations.

- Ruby's public site reported Ruby 4.0.3 as the latest stable version. Re-checked before scaffolding on 2026-05-03.
- RubyGems listed Rails 8.1.3 as the latest Rails gem release. Re-checked before scaffolding on 2026-05-03.
- Rails 8.0 introduced the default authentication generator, Propshaft by default, Solid Cable, Solid Cache, and Solid Queue.
- Rails 8.1 release notes list Active Job Continuations, Structured Event Reporting, Local CI, Markdown rendering, command-line credentials fetching, and registry-free Kamal deployment improvements.
- The OpenAI API still authenticates with API keys. API keys must stay server-side and must not be exposed to browsers.
- OpenAI's Codex CLI supports `codex login` with ChatGPT OAuth, device-code auth, or an API key.
- OpenAI's Codex App Server documentation exposes account auth methods for API key, ChatGPT-managed browser login, ChatGPT device-code login, and experimental externally managed ChatGPT tokens.
- Codex App Server account state can include ChatGPT plan type, and its account surface can read ChatGPT/Codex rate limits.
- OpenAI documents ChatGPT-managed Codex auth for trusted private automation when users need ChatGPT/Codex rate limits instead of API key usage, while still saying API keys are the right default for most CI/CD jobs.
- Ideal Magic's v1 AI path is Codex App Server ChatGPT-managed auth. It must not claim generic OpenAI API OAuth support or use ChatGPT tokens for arbitrary Responses API calls outside the documented Codex App Server surface.
- Scryfall provides public card data and asks clients to stay under 10 requests per second and use bulk data for large workloads.
- The Commander format requires exactly 100 cards including the commander, singleton rules except allowed exceptions, and commander color identity restrictions.
- The official Commander banned list checked on 2026-05-04 contains 44 explicitly banned card names plus category bans for ante cards, cards Wizards removed from constructed formats, and Conspiracy-type cards. The latest visible official update affecting this snapshot was the 2024-09-23 quarterly update.
- Wizards' Fan Content Policy allows free fan content with required unofficial disclaimers and limits on trademarks, payments, and access restrictions.
- Archidekt has visible public API behavior for public decks but sparse documentation. Treat it as an adapter that may break.
- Moxfield has public deck pages and a public GitHub organization, but no clearly documented official public API was found. Treat direct API integration as unstable until proven.

Reference links:

- Ruby: https://www.ruby-lang.org/en/downloads/
- Rails gem: https://rubygems.org/gems/rails
- Rails 8.0 release notes: https://guides.rubyonrails.org/8_0_release_notes.html
- Rails 8.1 release notes: https://guides.rubyonrails.org/8_1_release_notes.html
- Tailwind CSS for Rails: https://tailwindcss.com/docs/installation/framework-guides/ruby-on-rails
- OpenAI API authentication: https://developers.openai.com/api/reference/overview#authentication
- Codex CLI login: https://developers.openai.com/codex/cli/reference#codex-login
- Codex App Server auth endpoints: https://developers.openai.com/codex/app-server#auth-endpoints
- Codex ChatGPT-managed auth in CI/CD: https://developers.openai.com/codex/auth/ci-cd-auth
- Scryfall API rate guidance: https://scryfall.com/docs/faqs/i-m-having-trouble-accessing-the-scryfall-api-or-i-m-blocked-17
- Commander rules: https://mtgcommander.net/index.php/rules/
- Commander banned list: https://mtgcommander.net/index.php/banned-list/
- Commander September 2024 quarterly update: https://mtgcommander.net/index.php/2024/09/23/september-2024-quarterly-update/
- Wizards Fan Content Policy: https://company.wizards.com/en/legal/fancontentpolicy
- Archidekt public API discussion: https://archidekt.com/forum/thread/16962481
- Moxfield public organization: https://github.com/moxfield

## Scrybase Consolidation Notes

Scrybase was reviewed on 2026-05-04 before retirement. Ideal Magic replaces it as Stephen's single primary Magic project.

Product concepts to preserve:

- Collection ownership and demand pressure.
- Deck revisions, diffs, and revision performance.
- Combo, cut, upgrade, and owned-card intelligence.
- Goldfish consistency simulation for opening hands, land drops, curve hits, commander timing, and card access.
- Game-night sessions with player check-in, deck registration, pod seating, and result recording.
- Matchup notes tied to decks, commanders, opponents, pods, and sessions.
- Meta trends for decks, commanders, players, pods, win conditions, salt, and social friction.
- Public deck and session share links with opt-in revocation.
- Export surfaces for decks, analysis, collection summaries, and meta reports.
- Operator status, backup, restore, and smoke-flow discipline.

Implementation rule: preserve these product ideas, not Scrybase's Python, FastAPI, Astro, Elysia, OpenTUI, or rewrite-migration architecture.

## Product Constraints

- Ideal Magic must work from public deck URLs and text exports before depending on provider account linking.
- Collection features must start from user-provided exports and manual entry before depending on provider account linking.
- Ideal Magic must not store Archidekt, Moxfield, ChatGPT, OpenAI, or other third-party passwords.
- User-facing AI evaluation must use Codex App Server ChatGPT-managed account auth as the exclusive v1 model path.
- Codex account credential material must be isolated per user or per serialized workflow stream, treated like a password, and never committed, logged, pasted into tickets, or exposed to browsers.
- Rails should store only the minimum Codex account metadata needed for UX, auditing, and scheduling, such as auth mode, displayed email, plan type when returned, rate-limit snapshots, and timestamps.
- Do not implement bring-your-own OpenAI API key mode, admin-owned API key mode, or app-owned per-token API billing for v1 unless Stephen explicitly changes the product direction later.
- WotC-owned names, card text, art, and symbols require fan-content care. Do not place core access behind a paywall without legal review.
- AI output is advice, not rules authority. Commander legality and card facts must come from deterministic data and source-backed rules, not model guesses.
- Every score must have evidence, a rubric version, and enough explanation that users can challenge it.
- Collection-aware recommendations must distinguish owned-card opportunities, missing-card gaps, budget context, and optional purchases. Do not turn collection tooling into a marketplace or finance product.
- Game-night history, player records, matchup notes, and private playgroup context are private by default and must be opt-in for sharing or AI evaluation.
- Salt score, salt rating, and overall social friction are first-class v1 scoring outputs. They must be evidence-backed, versioned with the rubric, and presented as conversation aids rather than moral judgments about a player or deck.
- The UX must be fast on a phone at a table, not merely pretty on a desktop monitor.

## Target Stack

### Application

- Ruby latest stable, pinned in `.ruby-version` and the Docker image.
- Rails latest stable, pinned in `Gemfile.lock`.
- PostgreSQL latest stable supported by the selected Ubuntu and Docker runtime.
- Puma web server.
- Solid Queue for background analysis jobs.
- Solid Cache for Rails caching.
- Solid Cable for realtime analysis updates if realtime UX needs it.
- Active Storage for generated exports and optional user-uploaded deck files.
- Action Mailer for account verification, password reset, and notifications.
- Rails authentication generator as the v1 auth baseline.
- Passkeys/WebAuthn as a later auth hardening feature after password login is stable.

### Frontend

- Hotwire Turbo Drive, Frames, and Streams for navigation and live updates.
- Stimulus for interaction-heavy controls.
- Tailwind CSS v4 through `tailwindcss-rails`.
- ViewComponent or an equivalent Rails-native component layer for reusable, testable UI.
- Accessible HTML first. JavaScript enhances workflows; it does not own core rendering.
- Optional TypeScript and web workers only for service-worker logic, local simulations, IndexedDB, or charting complexity that clearly earns a build step.

### AI And Analysis

- Codex App Server through a small Rails service boundary.
- Codex-managed ChatGPT browser OAuth or device-code login for user account linking.
- ChatGPT/Codex account plan metadata and rate-limit snapshots when returned by Codex.
- Structured outputs for scorecards and explanations.
- Deterministic pre-analysis before model calls.
- Prompt, rubric, and model versioning in the database.
- Replayable analysis runs.
- Evaluation fixtures for known decks across precon, casual, upgraded, high-power, and cEDH-like ranges.
- Salt and social-friction fixtures for high-friction cards, play patterns, combos, stax, mass land denial, extra turns, theft, chaos, repetitive locks, and mismatch-prone decks.
- Collection-aware recommendations from owned cards, missing cards, demand pressure, and role gaps.
- Real-meta recommendations from sessions, results, matchup notes, win conditions, and deck revision history.
- Model, latency, rate-limit, token-usage-if-reported, and failure telemetry per analysis run.

### Data Sources

- Scryfall bulk data as the primary card corpus.
- Commander rules and banlist source snapshots.
- Public Archidekt deck URLs.
- Public Moxfield deck URLs.
- User-pasted decklists and exported text files.
- User-provided collection exports and manual collection entries.
- Recorded game-night sessions, pod results, matchup notes, and deck revisions.
- Future optional sources: Manabox exports, MTGGoldfish exports, EDHREC-derived tags if licensing and API access allow.

### Deployment

- Ubuntu server VM.
- `ideal-magic.com` behind Caddy-managed TLS.
- Docker Compose for local and self-hosted production.
- systemd unit for the Compose app.
- systemd timers or cron-compatible scripts for backups, Scryfall sync, and health checks.
- PostgreSQL volume backups with restore drills.
- No hard dependency on external PaaS.

## Target Repo Shape

```text
ideal-magic/
  AGENTS.md
  app/
    components/
    controllers/
    jobs/
    models/
    services/
    views/
  config/
  db/
    migrate/
    seeds/
  docs/
    analysis-rubric.md
    deployment.md
    provider-integrations.md
    product-scope.md
    security.md
  infra/
    caddy/
    systemd/
  lib/
    ideal_magic/
  test/
    fixtures/
    system/
  docker-compose.yml
  Dockerfile
  README.md
  BUILD.md
```

## Phase Status Summary

- [x] Phase 0 - Freeze product charter and repo rules.
- [x] Phase 1 - Scaffold the Rails foundation.
- [ ] Phase 2 - Build the data model and card corpus pipeline.
- [ ] Phase 3 - Build authentication, accounts, and Codex account-auth boundaries.
- [ ] Phase 4 - Build deck import and provider adapters.
- [ ] Phase 5 - Build deterministic Commander analysis.
- [ ] Phase 6 - Build Codex evaluation pipeline.
- [ ] Phase 7 - Build the deck evaluation UX.
- [ ] Phase 8 - Build collection and ownership intelligence.
- [ ] Phase 9 - Build pod evaluation, sessions, and game-night results.
- [ ] Phase 10 - Build matchup journal and meta analytics.
- [ ] Phase 11 - Build the PWA experience.
- [ ] Phase 12 - Harden security, observability, and admin operations.
- [ ] Phase 13 - Ship self-hosted deployment.
- [ ] Phase 14 - Run beta, calibrate scoring, and prepare v1.

## Phase 0 - Freeze Product Charter And Repo Rules

### Objectives

- [x] Turn the idea into stable product, architecture, and operating guidance.
- [x] Make future agents start from the same constraints.
- [x] Capture legal, provider, and OpenAI feasibility boundaries before code exists.

### Work Checklist

- [x] Confirm the app name, domain, and product positioning in `README.md`.
- [x] Add repo-local `AGENTS.md` if Stephen wants repo-specific rules beyond `/Users/sawyer/github/AGENTS.md`.
- [x] Create `docs/analysis-rubric.md` with the first scoring rubric.
- [x] Create `docs/provider-integrations.md` with the allowed provider integration policy.
- [x] Create `docs/security.md` with auth, token, secret, and privacy rules.
- [x] Create `docs/deployment.md` with the intended Ubuntu, Caddy, Docker Compose, and systemd shape.
- [x] Add a WotC fan-content disclaimer plan.
- [x] Decide whether the repo is private or public.
- [x] Decide the license or explicitly mark licensing as pending.

### Exit Criteria

- [x] A future agent can answer what Ideal Magic is, what v1 must ship, and what is out of scope.
- [x] A future agent cannot accidentally plan around generic OpenAI API OAuth or unsupported ChatGPT token passthrough.
- [x] The legal and provider boundaries are written before implementation.

### Verification

- [x] `rg -n "ChatGPT subscription|OpenAI|Moxfield|Archidekt|Fan Content|Commander" README.md BUILD.md docs`
- [x] `git diff --check`

## Phase 1 - Scaffold The Rails Foundation

### Objectives

- [x] Create a modern Rails app with boring local startup.
- [x] Pin current stable Ruby and Rails versions after live verification.
- [x] Establish quality gates before feature work.

### Work Checklist

- [x] Re-check latest stable Ruby and Rails versions from official sources.
- [x] Install or select the verified Ruby version locally.
- [x] Scaffold Rails in the repo root with PostgreSQL and Tailwind CSS.
- [x] Pin `.ruby-version`, `Gemfile`, `Gemfile.lock`, and Docker base image consistently.
- [x] Add Hotwire, Stimulus, Tailwind, and the chosen component layer.
- [x] Add Rails authentication generator output or an explicit auth baseline.
- [x] Add Brakeman, RuboCop, ERB linting, and bundle audit tooling.
- [x] Add Minitest or RSpec decision and stick to one primary test framework.
- [x] Add root scripts for setup, lint, test, security, build, and verify.
- [x] Add `.env.example` without secrets.
- [x] Add health and readiness endpoints.
- [x] Add a simple home/dashboard route that proves the app boots.

### Exit Criteria

- [x] `bin/setup` prepares a fresh development environment.
- [x] `bin/dev` starts the local web app.
- [x] The root verify command runs all current checks.
- [x] The app can connect to PostgreSQL locally.

### Verification

- [x] `bundle exec rubocop`
- [x] `bundle exec brakeman`
- [x] `bin/rails test`
- [x] `bin/rails db:prepare`
- [x] `bin/rails assets:precompile`
- [x] `bin/verify`

## Phase 2 - Build The Data Model And Card Corpus Pipeline

### Objectives

- [ ] Make local card data trustworthy, queryable, and refreshable.
- [ ] Keep card facts deterministic and separate from AI interpretation.
- [ ] Support Commander legality, card tags, and deck analysis features.

### Work Checklist

- [x] Model users, decks, deck cards, commanders, provider links, card printings, oracle cards, sets, rulings, legality snapshots, analysis runs, scorecards, pod evaluations, salt/social-friction evidence, and audit events.
- [x] Add database indexes for deck ownership, card lookup, provider IDs, card names, oracle IDs, and analysis history.
- [x] Build Scryfall bulk-data ingestion with polite user-agent headers and rate-limit discipline.
- [x] Store source snapshot metadata for every card corpus refresh.
- [x] Normalize card names, faces, color identity, mana value, type lines, oracle text, legalities, and image URIs.
- [x] Add Commander banlist and rules snapshot storage.
- [x] Add internal card tags for ramp, fast mana, tutors, draw, protection, removal, stack interaction, board wipes, stax, combos, graveyard use, lands, win conditions, salt drivers, and social-friction patterns.
- [x] Add curated salt taxonomy and override data for cards and play patterns that deterministic card facts cannot classify reliably.
- [x] Add curated override files or admin screens for tags the card corpus cannot infer reliably.
- [ ] Add import fixtures for representative Commander decks.
- [ ] Add data refresh jobs through Solid Queue.

### Exit Criteria

- [ ] The app can answer card facts without calling OpenAI.
- [ ] Card data refreshes are repeatable and auditable.
- [ ] Commander legality checks have deterministic source data.
- [ ] Salt and social-friction tags are source-controlled, reviewable, and separated from raw Scryfall card facts.

### Verification

- [x] Card corpus unit tests.
- [x] Scryfall ingestion tests against fixture payloads.
- [x] Commander rules and banlist snapshot storage tests.
- [ ] Commander legality tests.
- [x] Salt taxonomy and override tests.
- [ ] Database migration reset from scratch.
- [ ] Background job smoke test for data refresh.

## Phase 3 - Build Authentication, Accounts, And Codex Account-Auth Boundaries

### Objectives

- [ ] Let users own deck history and analysis settings.
- [ ] Make Codex account usage explicit, secure, and honest.
- [ ] Keep future auth providers replaceable.

### Work Checklist

- [ ] Implement email/password auth with secure sessions.
- [ ] Add email verification and password reset.
- [ ] Add account settings for display name, timezone, and preferred units.
- [ ] Add user profile fields needed for playgroup sessions, public display names, and private note attribution.
- [ ] Add Codex App Server account login start, completion, cancel, logout, and account-read flows.
- [ ] Add Codex browser OAuth and device-code UX without collecting ChatGPT passwords.
- [ ] Add isolated Codex credential storage per user or serialized workflow stream.
- [ ] Add per-user and global analysis quota controls backed by app policy and Codex rate-limit state.
- [ ] Add visible rate-limit and expected runtime guidance before expensive analysis.
- [ ] Add model, rate-limit, token-usage-if-reported, and latency tracking per analysis run.
- [ ] Add account deletion and data export flows.
- [ ] Ensure account export includes decks, analyses, collection records, sessions created by the user, matchup notes, and audit metadata that belongs to the account.
- [ ] Add provider account link placeholders without requesting third-party passwords.
- [ ] Add token-cache deletion and auth disconnect flows that clear local Codex credentials.

### Exit Criteria

- [ ] Users can sign up, sign in, reset passwords, and delete their account.
- [ ] Codex account-auth mode, plan metadata when available, and rate-limit state are clear to users and operators.
- [ ] No browser can see OpenAI API keys or Codex access tokens.
- [ ] The app does not imply generic OpenAI API OAuth or arbitrary Responses API subscription passthrough is supported.

### Verification

- [ ] Auth system tests.
- [ ] Codex credential isolation and disconnect tests.
- [ ] Browser tests for signup, login, logout, password reset, and account deletion.
- [ ] Security review of Codex credential handling.

## Phase 4 - Build Deck Import And Provider Adapters

### Objectives

- [ ] Make deck intake reliable before scoring.
- [ ] Support public deck links from Archidekt and Moxfield.
- [ ] Keep provider-specific parsing isolated and replaceable.

### Work Checklist

- [ ] Define a provider adapter interface with fetch, parse, normalize, and refresh methods.
- [ ] Add pasted decklist import.
- [ ] Add text file import.
- [ ] Add public Archidekt deck URL import.
- [ ] Add public Moxfield deck URL import.
- [ ] Add provider profile URL discovery only if it can be done politely and without private auth.
- [ ] Add provider refresh jobs with backoff, cache, and clear error states.
- [ ] Add deck version history and diffing.
- [ ] Store deck revision snapshots whenever imports, edits, or manual card changes alter a deck.
- [ ] Add duplicate card, missing card, unknown card, and commander detection workflows.
- [ ] Add manual deck edit fallback for failed imports.
- [ ] Add source attribution on every imported deck.
- [ ] Add deck export formats for plain text, CSV, and JSON before provider import work is considered complete.
- [ ] Add provider adapter fixtures from real public deck examples.

### Exit Criteria

- [ ] A user can import a Commander deck by paste.
- [ ] A user can import a public Archidekt deck URL.
- [ ] A user can import a public Moxfield deck URL.
- [ ] Failed imports produce actionable errors.
- [ ] Provider changes do not break the rest of the app.

### Verification

- [ ] Adapter unit tests.
- [ ] Fixture-based provider parser tests.
- [ ] Browser import tests.
- [ ] Rate-limit and retry tests.
- [ ] Manual smoke import of at least three real public decks per provider.

## Phase 5 - Build Deterministic Commander Analysis

### Objectives

- [ ] Produce useful baseline analysis without model calls.
- [ ] Make scores explainable from computed features.
- [ ] Avoid using an LLM as a rules engine.

### Work Checklist

- [ ] Validate deck size, commander presence, singleton rules, color identity, and legality.
- [ ] Compute mana curve, color requirements, land count, source count, ramp count, draw count, tutor count, interaction count, wipe count, protection count, graveyard dependence, and win condition markers.
- [ ] Detect known combos through a curated combo graph.
- [ ] Compute role/category balance and cut candidates from tags, mana value, duplicate effects, off-plan cards, and recorded dead-draw notes when available.
- [ ] Detect fast mana and high-power staples through tag rules.
- [ ] Compute deterministic salt score from salt-tagged cards, high-friction mechanics, denial density, combo compactness, repetitive locks, extra-turn loops, theft/control effects, chaos effects, mass land denial, and expected recovery burden on opponents.
- [ ] Compute salt rating bands from salt score with stable labels that are clear without being inflammatory.
- [ ] Compute overall social friction score from salt, speed mismatch risk, power ambiguity, interaction asymmetry, stax/lock likelihood, combo opacity, game-length pressure, and Rule 0 disclosure needs.
- [ ] Estimate speed from ramp, tutors, curve, win conditions, and goldfish heuristics.
- [ ] Estimate consistency from mana, redundancy, card draw, tutors, curve, and opening-hand heuristics.
- [ ] Estimate interaction from count, type mix, mana efficiency, and coverage.
- [ ] Estimate power from deterministic feature bands before AI adjustment.
- [ ] Add simulation jobs for opening hand and early-turn probability checks where feasible.
- [ ] Store goldfish simulation outputs for average lands in opener, mulligan rate, land-drop rates, curve-hit rates, commander-cast timing, and card-access rates.
- [ ] Store feature vectors with every analysis run.
- [ ] Create benchmark decks for precon, upgraded precon, casual, optimized, high-power, and cEDH-like ranges.

### Exit Criteria

- [ ] Every deck can receive a deterministic score draft.
- [ ] Every deterministic score exposes the facts that drove it.
- [ ] Every deck can receive salt score, salt rating, and overall social friction outputs without calling OpenAI.
- [ ] The app can run baseline analysis while OpenAI is disabled.

### Verification

- [ ] Unit tests for feature extraction.
- [ ] Commander legality regression tests.
- [ ] Salt score, salt rating, and social-friction scoring tests against calibrated fixtures.
- [ ] Benchmark deck score snapshot tests.
- [ ] Performance test for large batch analysis.

## Phase 6 - Build Codex Evaluation Pipeline

### Objectives

- [ ] Add AI judgment on top of deterministic facts.
- [ ] Make the model produce structured, auditable scorecards.
- [ ] Keep model latency, rate-limit usage, and variance under control.

### Work Checklist

- [ ] Create a Rails service for Codex App Server JSON-RPC calls.
- [ ] Create isolated Codex runtime lifecycle management for evaluation jobs.
- [ ] Read Codex account state and ChatGPT/Codex rate limits before starting expensive evaluations.
- [ ] Define JSON schema for AI scorecards, including salt score, salt rating, social friction score, friction drivers, and Rule 0 talking points.
- [ ] Define JSON schema extensions for collection-aware recommendations, real-meta evidence, post-game review prompts, and matchup memory summaries once those phases exist.
- [ ] Define prompt versions for single-deck analysis.
- [ ] Define prompt versions for pod analysis.
- [ ] Pass deterministic feature vectors, decklist summaries, commander identity, combo candidates, salt/social-friction evidence, and rubric text to the model.
- [ ] Pass owned-card gaps, session history, matchup notes, and meta summaries only for workflows where the user explicitly requests that context.
- [ ] Instruct the model to cite only provided facts and mark uncertainty.
- [ ] Add retries, timeouts, request IDs, auth failure states, and rate-limit failure states.
- [ ] Add moderation or abuse safeguards for user-provided deck descriptions and prompts.
- [ ] Add model selection settings with a current default and pinned snapshot option when available.
- [ ] Add fast and high-quality evaluation modes when the Codex model catalog supports them.
- [ ] Add evaluator tests with recorded fixtures or mocked responses.
- [ ] Add human-review admin tools for score calibration.
- [ ] Add red-team fixtures for hallucination, illegal decks, joke decks, and malformed imports.

### Exit Criteria

- [ ] AI analysis returns valid structured scorecards.
- [ ] Invalid model output is rejected and retried or surfaced as a failed run.
- [ ] Deterministic facts remain visible beside AI interpretation.
- [ ] AI salt/social-friction explanations cite deterministic evidence and do not shame players for deck choices.
- [ ] Model, latency, rate-limit state, and token usage when reported are stored per run.

### Verification

- [ ] Codex App Server client unit tests.
- [ ] Schema validation tests.
- [ ] Prompt fixture tests.
- [ ] Analysis job integration test with mocked Codex App Server.
- [ ] Optional live smoke test gated by available Codex account auth.

## Phase 7 - Build The Deck Evaluation UX

### Objectives

- [ ] Make single-deck evaluation beautiful, fast, and useful.
- [ ] Give users both a quick answer and the evidence behind it.
- [ ] Make mobile the primary table-side experience.

### Work Checklist

- [ ] Build dashboard with recent decks, analyses, imports, and queued jobs.
- [ ] Add dashboard modules for collection gaps, demand pressure, open sessions, recent results, and matchup reminders once those domains exist.
- [ ] Build deck detail page with commander, colors, source, card list, tags, curve, and import history.
- [ ] Build analysis run page with power, speed, interaction, consistency, salt score, salt rating, and overall social friction scores.
- [ ] Show confidence, evidence, and improvement priorities for each score.
- [ ] Show salt and social-friction evidence with neutral language, card/play-pattern drivers, and practical table-disclosure guidance.
- [ ] Add "what changed since last analysis" diffs.
- [ ] Add recommendation sections for mana, draw, ramp, interaction, win conditions, salt reduction, and social fit.
- [ ] Add recommendation sections for owned upgrades, missing high-demand cards, budget context, and real-meta adjustments once collection and session evidence exist.
- [ ] Add user feedback controls for score agreement and notes.
- [ ] Add shareable public analysis links with privacy controls.
- [ ] Add export to Markdown, text, and JSON.
- [ ] Add deck export to text, CSV, and JSON from deck detail.
- [ ] Add loading, queued, running, failed, stale, and complete states.
- [ ] Add mobile bottom navigation and desktop sidebar navigation.
- [ ] Add responsive card list controls for search, tags, categories, and role filters.

### Exit Criteria

- [ ] Users can understand a deck's strengths and weaknesses within one screen.
- [ ] Users can drill into score evidence without losing context.
- [ ] Users can understand why a deck may feel salty or socially high-friction without the UI treating salt as inherently bad.
- [ ] The UI remains usable on phone, tablet, and desktop widths.

### Verification

- [ ] Component tests.
- [ ] System tests for import to analysis completion.
- [ ] System tests for salt/social-friction score display, evidence drilldown, and export content.
- [ ] Playwright or Rails system screenshots for mobile and desktop.
- [ ] Accessibility checks for keyboard navigation, labels, contrast, and reduced motion.

## Phase 8 - Build Collection And Ownership Intelligence

### Objectives

- [ ] Let users build and tune from cards they actually own.
- [ ] Make missing cards, duplicate demand, and owned upgrades visible across the deck library.
- [ ] Keep collection tooling useful without becoming a finance or marketplace product.

### Work Checklist

- [ ] Model collection cards, collection imports, collection unresolved entries, wishlist items, and deck ownership snapshots.
- [ ] Add indexes for user collection lookup, normalized card names, ownership gaps, and demand pressure.
- [ ] Add pasted collection import.
- [ ] Add uploaded text and CSV-like collection import.
- [ ] Add manual collection add, edit, remove, and quantity adjustment flows.
- [ ] Add unresolved-card review for ambiguous or unknown collection entries.
- [ ] Compute owned versus missing cards for every deck.
- [ ] Compute demand pressure for cards needed across multiple decks.
- [ ] Add collection-aware upgrade suggestions from owned cards that fit a deck's color identity, tags, and role gaps.
- [ ] Add optional budget and price context only when sourced from stored Scryfall price snapshots and clearly marked as stale-prone.
- [ ] Add wishlist and acquisition planning without marketplace, trading, or checkout flows.
- [ ] Add collection import history, parser version, source label, and import rollback or correction workflow.
- [ ] Add exports for collection summary, deck gaps, and demand pressure.

### Exit Criteria

- [ ] A user can import and maintain a collection.
- [ ] A user can open any deck and see owned, missing, and shortfall counts.
- [ ] A user can see which missing cards matter across multiple decks.
- [ ] Recommendations distinguish owned-card opportunities from possible purchases.
- [ ] Collection data remains private unless explicitly exported or shared.

### Verification

- [ ] Collection model and parser tests.
- [ ] Collection import fixture tests.
- [ ] Ownership and demand-pressure service tests.
- [ ] Collection-aware recommendation tests.
- [ ] Browser tests for import, manual edits, deck gaps, and exports.

## Phase 9 - Build Pod Evaluation, Sessions, And Game-Night Results

### Objectives

- [ ] Help players compare decks before a Commander game.
- [ ] Support real game-night setup: sessions, players, check-in, deck registration, pod seating, and result recording.
- [ ] Detect mismatch, speed gaps, interaction imbalance, and likely play-pattern issues.
- [ ] Produce a useful Rule 0 conversation brief.

### Work Checklist

- [ ] Model pods, pod slots, pod decks, pod analysis runs, and shared pod links.
- [ ] Model sessions, players, session players, session decks, pod seats, pod results, and shared session links.
- [ ] Let users create a pod from 2 to 4 decks for v1.
- [ ] Support guest deck submission by public link or paste.
- [ ] Let users create a game-night session with date, location, notes, and status.
- [ ] Add player check-in and deck registration workflows.
- [ ] Add pod preview and seating from checked-in player/deck pairs.
- [ ] Add result recording with winner, draw state, turns, win condition, and notes.
- [ ] Preserve deck revision and analysis snapshot used for each pod seat.
- [ ] Compute score spread, average, outliers, and matchup warnings.
- [ ] Compute pod-level salt spread, average social friction, friction outliers, and mismatch warnings.
- [ ] Detect likely archenemy decks, pubstomp risks, durdle risks, and interaction gaps.
- [ ] Compute pod seating quality from score spread, social-friction spread, color/archetype repetition, and prior matchup history.
- [ ] Generate a Rule 0 brief with power band, speed expectations, combo/stax notes, salt/social-friction notes, and suggested swaps.
- [ ] Show pod balance visually without hiding details.
- [ ] Add printable and shareable pod summary.
- [ ] Add public session summary links with opt-in sharing and revocation.
- [ ] Add "find closer decks from my library" recommendations.

### Exit Criteria

- [ ] A pod can be created, analyzed, shared, and revised.
- [ ] A game-night session can be created, checked in, seated, scored, and reviewed.
- [ ] Mismatch warnings are specific and evidence-backed.
- [ ] Pod salt/social-friction warnings identify likely table experience issues without overstating certainty.
- [ ] Pod analysis helps players choose decks, not just assign numbers.
- [ ] Session history creates durable inputs for meta analytics and post-game tuning.

### Verification

- [ ] Pod model and service tests.
- [ ] Session, player, check-in, seating, and result model/service tests.
- [ ] Pod UI system tests.
- [ ] Session workflow browser tests from create through result recording.
- [ ] Pod salt/social-friction fixture tests across low-salt, mixed-salt, and high-friction pods.
- [ ] Benchmark pod fixture tests across balanced and mismatched pods.
- [ ] Public session share tests.

## Phase 10 - Build Matchup Journal And Meta Analytics

### Objectives

- [ ] Preserve human matchup context that decklists and scores cannot capture.
- [ ] Turn recorded sessions into useful deck, commander, player, pod, and win-condition trends.
- [ ] Use real playgroup history to improve recommendations without overstating small samples.

### Work Checklist

- [ ] Model matchup notes, matchup tags, note links to decks, commanders, players, pods, and sessions.
- [ ] Add matchup note create, edit, delete, search, and tag filters.
- [ ] Add pre-game context surfaces for prior notes tied to a commander, opponent, deck, or pod.
- [ ] Add post-game review prompts for wins, losses, draws, short games, stalls, overperformers, dead draws, and missing cards.
- [ ] Compute deck stats: games, wins, draws, average turns, last played, win rate, and confidence by sample size.
- [ ] Compute commander meta: appearances, wins, win rate, average score band, salt/social-friction history, and recent trend.
- [ ] Compute player and pod history without turning the app into a public ranking or shaming surface.
- [ ] Compute win-condition breakdowns and recurring loss patterns.
- [ ] Compute revision performance by connecting results to deck revisions.
- [ ] Compute salt and social-friction trends from recorded results, notes, and deterministic evidence.
- [ ] Add "what changed since this deck last won/lost" views.
- [ ] Add meta-aware recommendations that cite sample size and recency.
- [ ] Add admin/operator recompute jobs for derived meta tables.

### Exit Criteria

- [ ] Users can record and retrieve useful matchup notes.
- [ ] Decks show performance and revision history from real games.
- [ ] Meta dashboards summarize trends without pretending thin data is certain.
- [ ] Recommendations can cite real playgroup evidence separately from deck-construction facts.

### Verification

- [ ] Matchup note model, service, and search tests.
- [ ] Meta analytics service tests.
- [ ] Revision performance tests.
- [ ] Post-game prompt tests.
- [ ] Browser tests for journal, meta dashboard, and deck performance views.
- [ ] Privacy tests for private notes and share boundaries.

## Phase 11 - Build The PWA Experience

### Objectives

- [ ] Make Ideal Magic installable and reliable on mobile and desktop.
- [ ] Support table-side use with poor network conditions.
- [ ] Keep offline behavior honest and predictable.

### Work Checklist

- [ ] Add web app manifest with proper name, short name, icons, theme color, display mode, screenshots, and app shortcuts.
- [ ] Add service worker with app-shell caching.
- [ ] Add offline fallback pages.
- [ ] Cache recent decks and recent analysis summaries for read-only offline access.
- [ ] Cache recent collection gaps, open session summaries, pod briefs, and matchup notes for read-only offline access when privacy settings allow.
- [ ] Add background refresh for stale imported decks where supported.
- [ ] Add install prompts that respect browser behavior and user choice.
- [ ] Add iOS home-screen metadata and icon coverage.
- [ ] Add Android maskable icons.
- [ ] Add desktop PWA install polish.
- [ ] Add cache versioning and update notification behavior.
- [ ] Add IndexedDB only if recent-deck offline storage outgrows simple browser cache.
- [ ] Add share target support for deck URLs if browser support and routing are reliable.

### Exit Criteria

- [ ] The app is installable from supported mobile and desktop browsers.
- [ ] Recent deck evaluations can be opened offline.
- [ ] Offline states never pretend fresh AI analysis can run without network.
- [ ] Offline states never pretend imports, sync, sharing changes, or new result recording have reached the server.
- [ ] PWA updates do not trap users on stale assets.

### Verification

- [ ] Lighthouse PWA checks.
- [ ] Browser install checks on desktop.
- [ ] Mobile viewport install and offline checks.
- [ ] Service worker cache update test.
- [ ] No-overlap responsive screenshots.

## Phase 12 - Harden Security, Observability, And Admin Operations

### Objectives

- [ ] Make the app safe to run publicly.
- [ ] Give Stephen operational visibility without SaaS lock-in.
- [ ] Prevent runaway AI spend and abusive traffic.

### Work Checklist

- [ ] Add rate limiting for auth, imports, analysis creation, and public share pages.
- [ ] Add CSRF, secure cookie, CORS, CSP, and security header review.
- [ ] Add audit events for auth, import, analysis, provider refresh, key changes, and admin actions.
- [ ] Add audit events for collection imports, session sharing, result recording, matchup note changes, and meta recomputes.
- [ ] Add admin dashboard for users, jobs, imports, collection import failures, analysis failures, provider health, public shares, and AI spend.
- [ ] Add structured logs with request IDs.
- [ ] Add operator status page or command showing app version, database status, job queues, card corpus freshness, analysis counts, collection counts, session counts, share counts, and backup recency.
- [ ] Add error reporting route or local log workflow.
- [ ] Add OpenTelemetry-compatible instrumentation if it earns the complexity.
- [ ] Add database backup and restore scripts.
- [ ] Add abuse controls for public imports and share links.
- [ ] Add privacy controls for deck visibility and analysis sharing.
- [ ] Add privacy controls for collection visibility, matchup notes, player names, session summaries, and pod result shares.
- [ ] Add Terms, Privacy, and Fan Content disclaimer pages.

### Exit Criteria

- [ ] Public deployment has sane abuse resistance.
- [ ] AI spend is bounded by quotas and visible in admin.
- [ ] Backups and restores are documented and tested.
- [ ] Security docs match implemented behavior.

### Verification

- [ ] Brakeman clean or documented accepted findings.
- [ ] Bundle audit clean or documented accepted findings.
- [ ] Rate-limit tests.
- [ ] Backup and restore drill.
- [ ] Manual admin workflow smoke test.

## Phase 13 - Ship Self-Hosted Deployment

### Objectives

- [ ] Make `ideal-magic.com` deployable on Stephen's Ubuntu VM.
- [ ] Keep deployment boring, inspectable, and recoverable.
- [ ] Use Caddy as the public TLS edge.

### Work Checklist

- [ ] Add production Dockerfile for Rails.
- [ ] Add `docker-compose.yml` for app, worker, database, and optional internal Caddy.
- [ ] Add `compose.production.yml` or documented production overrides.
- [ ] Add Caddyfile for `ideal-magic.com`.
- [ ] Add systemd unit for Compose lifecycle.
- [ ] Add systemd timer for backups.
- [ ] Add environment variable contract for production.
- [ ] Add secret setup instructions using Rails credentials or environment secrets.
- [ ] Add database migration command for deploys.
- [ ] Add health check endpoint and Caddy upstream checks.
- [ ] Add operator status and backup commands for production troubleshooting.
- [ ] Add rollback and restore docs.
- [ ] Add first deploy runbook.

### Exit Criteria

- [ ] A fresh Ubuntu VM can run Ideal Magic from documented steps.
- [ ] Caddy terminates HTTPS for `ideal-magic.com`.
- [ ] App, worker, and database restart cleanly after reboot.
- [ ] Backups survive container replacement.

### Verification

- [ ] `docker compose build`
- [ ] `docker compose up -d`
- [ ] `docker compose exec web bin/rails db:migrate`
- [ ] `curl -fsS https://ideal-magic.com/up`
- [ ] Reboot smoke test on staging or production VM.
- [ ] Restore test into a fresh volume.

## Phase 14 - Run Beta, Calibrate Scoring, And Prepare V1

### Objectives

- [ ] Validate that scores match real Commander expectations.
- [ ] Improve the rubric from feedback without losing explainability.
- [ ] Ship a coherent v1 instead of endless feature creep.

### Work Checklist

- [ ] Recruit beta users with different Commander metas.
- [ ] Collect score disagreement feedback.
- [ ] Collect salt score, salt rating, and social-friction disagreement feedback.
- [ ] Collect collection-aware recommendation feedback from users with real inventories.
- [ ] Collect pod-session and matchup-journal feedback from real game nights.
- [ ] Create calibration decks for each power band.
- [ ] Create calibration decks for each salt rating and social-friction band.
- [ ] Create calibration pods and sessions for balanced, mismatched, salty, high-friction, and long-game tables.
- [ ] Tune deterministic scoring weights.
- [ ] Tune salt/social-friction weights separately from raw power so salty casual decks and clean high-power decks can be represented accurately.
- [ ] Tune meta-aware recommendation thresholds by sample size and recency.
- [ ] Tune AI prompt and rubric versions.
- [ ] Add changelog for scoring rubric changes.
- [ ] Define v1 launch feature set and freeze scope.
- [ ] Update `README.md` from planned state to shipped state.
- [ ] Remove obsolete planning sections once stable docs carry the truth.
- [ ] Tag v1 release.

### Exit Criteria

- [ ] Scores are useful enough for real pod decisions.
- [ ] Known benchmark decks land in expected bands.
- [ ] v1 docs describe shipped behavior, not aspiration.
- [ ] Future features are tracked separately from v1 build scope.

### Verification

- [ ] Benchmark suite score review.
- [ ] Salt/social-friction calibration review with real Commander players across multiple metas.
- [ ] Beta feedback review.
- [ ] Full `bin/verify`.
- [ ] Production smoke test.

## Initial Scoring Rubric Direction

Scores should be stored internally on a 0-100 scale and displayed in friendly bands. The first public UI should show both numeric scores and plain-language bands.

### Power

Power measures the deck's ability to win against prepared Commander tables.

Inputs include win condition density, fast mana, tutor density, compact combos, commander dependency, resilience, protection, card quality, mana efficiency, and known high-power patterns.

### Speed

Speed estimates how quickly the deck can present a meaningful win attempt or dominant board state.

Inputs include ramp profile, curve, fast mana, tutor access, opening-hand probabilities, combo compactness, and early-turn draw smoothing.

### Interaction

Interaction measures how well the deck can stop other players from winning and protect its own plan.

Inputs include instant-speed removal, stack interaction, board wipes, graveyard hate, artifact/enchantment answers, protection, stax, mana efficiency, and coverage across threat types.

### Consistency

Consistency measures how often the deck executes its intended plan.

Inputs include mana base quality, land count, color source count, card draw, selection, tutors, redundancy, curve, commander dependency, and dead-card risk.

### Pod Fit

Pod fit measures whether multiple decks are likely to produce a satisfying game together.

Inputs include score spread, speed spread, combo and stax profile, interaction distribution, win-condition clarity, salt spread, and social friction flags.

### Salt Score And Salt Rating

Salt score measures how likely a deck's cards and play patterns are to create frustration, resentment, or Rule 0 concern at a typical Commander table. Salt score is stored internally on a 0-100 scale. Salt rating is the human-readable band derived from the salt score.

Inputs include salt-tagged cards, stax and lock density, mass land denial, extra-turn loops, theft and control effects, chaos effects, tutor-to-combo pressure, deterministic win lines that are hard to interact with, repetitive play patterns, game-length extension, and the amount of table recovery burden imposed on opponents.

Salt rating labels must be neutral and useful. They should describe expected table impact rather than insult the deck or player.

### Overall Social Friction

Overall social friction measures how much Rule 0 conversation a deck or pod likely needs before play. It is related to salt, but not identical: a high-power cEDH deck can be low-friction in the right pod, while a casual deck can be high-friction if its game plan creates slow, repetitive, or unclear experiences.

Inputs include salt score, salt rating, power/speed mismatch risk, combo opacity, stax/lock likelihood, interaction asymmetry, commander reputation, game-length pressure, archetype expectations, and whether the deck's win conditions are easy for opponents to understand.

Social friction outputs must include practical disclosure prompts and suggested pod adjustments. They must not present social friction as a moral verdict.

### Documentation Requirement

When salt score, salt rating, or social friction work begins, update `docs/analysis-rubric.md`, `README.md`, exported score schemas, and any build/verify pipeline documentation in the same tranche so the product promise, rubric, UI, API/export behavior, and tests agree.

## V1 Non-Goals

- [ ] Native iOS or Android apps.
- [ ] Full rules-engine gameplay simulation.
- [ ] Private Archidekt or Moxfield account sync without official auth.
- [ ] Charging for WotC IP-backed fan content without legal review.
- [ ] Replacing Scryfall as the card data source.
- [ ] Building a Discord bot before the web app is useful.
- [ ] Building trading, collection finance, checkout, pricing speculation, or marketplace features.
- [ ] Supporting every MTG format before Commander is excellent.

## Future Feature Backlog

- [ ] ChatGPT app or GPT Action that can analyze a deck from inside ChatGPT.
- [ ] Browser share target for deck URLs.
- [ ] Deck improvement simulator with budget and salt constraints.
- [ ] Advanced multi-playgroup profiles with explicit member permissions.
- [ ] Commander recommendation engine from user preferences.
- [ ] Event-scale QR code deck submission and tournament-style seating.
- [ ] Public deck gallery and analysis leaderboard.
- [ ] Optional Discord bot for pod checks.
- [ ] Optional email summaries for deck changes and stale imports.
- [ ] Human-curated archetype taxonomy.
- [ ] Calibration mode where trusted users help tune scoring.
