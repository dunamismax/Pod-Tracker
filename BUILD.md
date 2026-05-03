# BUILD.md

Last drafted: 2026-05-03

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
- Do not claim users can sign in with ChatGPT or use their ChatGPT subscription for backend model calls unless OpenAI publishes an official third-party auth and billing flow that supports it.

## Build Decision

`Ideal Magic` is a Ruby on Rails web application for Commander deck and pod evaluation.

The approved product direction:

- Ruby and Rails latest stable at scaffold time.
- Rails monolith first, not a separate SPA and API unless the product earns that split later.
- PostgreSQL as the durable application database.
- Hotwire, Turbo, Stimulus, Tailwind CSS, and componentized Rails views for the primary UI.
- Rails-native background jobs, caching, and realtime features first.
- OpenAI Responses API for AI evaluation using server-side API credentials or an encrypted bring-your-own-API-key mode.
- PWA-first mobile and desktop experience.
- Docker Compose, Caddy, and systemd for Stephen's self-hosted Ubuntu deployment at `ideal-magic.com`.

## Current Repo Truth

The repo is currently an empty Git repository with planning docs being added first.

No Rails app, database schema, Docker runtime, deployment files, analysis engine, provider integrations, PWA assets, or production configuration exist yet.

## Current External Truth To Preserve

These references were checked while drafting this plan. Agents must re-check current versions before scaffolding or implementing external integrations.

- Ruby's public site reported Ruby 4.0.3 as the latest stable version.
- RubyGems listed Rails 8.1.3 as the latest Rails gem release.
- Rails 8.0 introduced the default authentication generator, Propshaft by default, Solid Cable, Solid Cache, and Solid Queue.
- Rails 8.1 release notes list Active Job Continuations, Structured Event Reporting, Local CI, Markdown rendering, command-line credentials fetching, and registry-free Kamal deployment improvements.
- The OpenAI API authenticates with API keys. API keys must stay server-side and must not be exposed to browsers.
- OpenAI's ChatGPT billing and API platform billing are separate systems. A ChatGPT Free, Plus, Pro, Business, Enterprise, or Education subscription cannot be assumed to pay for this app's backend API usage.
- ChatGPT Actions and ChatGPT Apps can authenticate ChatGPT to a third-party app, but that is not the same as a public "Sign in with ChatGPT" web login or a way to spend a user's ChatGPT subscription from Ideal Magic.
- OpenAI's platform docs recommend the Responses API for new text-generation apps.
- Scryfall provides public card data and asks clients to stay under 10 requests per second and use bulk data for large workloads.
- The Commander format requires exactly 100 cards including the commander, singleton rules except allowed exceptions, and commander color identity restrictions.
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
- OpenAI ChatGPT vs API billing: https://help.openai.com/en/articles/9039756
- OpenAI latest model guide: https://platform.openai.com/docs/guides/latest-model
- Scryfall API rate guidance: https://scryfall.com/docs/faqs/i-m-having-trouble-accessing-the-scryfall-api-or-i-m-blocked-17
- Commander rules: https://mtgcommander.net/index.php/rules/
- Wizards Fan Content Policy: https://company.wizards.com/en/legal/fancontentpolicy
- Archidekt public API discussion: https://archidekt.com/forum/thread/16962481
- Moxfield public organization: https://github.com/moxfield

## Product Constraints

- Ideal Magic must work from public deck URLs and text exports before depending on provider account linking.
- Ideal Magic must not store Archidekt, Moxfield, OpenAI, or other third-party passwords.
- OpenAI API costs must be explicit. Supported v1 options are app-owned API billing, admin-only API key, or encrypted user-provided API keys. ChatGPT subscription passthrough is blocked unless OpenAI ships an official flow.
- WotC-owned names, card text, art, and symbols require fan-content care. Do not place core access behind a paywall without legal review.
- AI output is advice, not rules authority. Commander legality and card facts must come from deterministic data and source-backed rules, not model guesses.
- Every score must have evidence, a rubric version, and enough explanation that users can challenge it.
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

- OpenAI Responses API through a small Rails service boundary.
- Structured outputs for scorecards and explanations.
- Deterministic pre-analysis before model calls.
- Prompt, rubric, and model versioning in the database.
- Replayable analysis runs.
- Evaluation fixtures for known decks across precon, casual, upgraded, high-power, and cEDH-like ranges.
- Cost, token, latency, and failure telemetry per analysis run.

### Data Sources

- Scryfall bulk data as the primary card corpus.
- Commander rules and banlist source snapshots.
- Public Archidekt deck URLs.
- Public Moxfield deck URLs.
- User-pasted decklists and exported text files.
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

- [ ] Phase 0 - Freeze product charter and repo rules.
- [ ] Phase 1 - Scaffold the Rails foundation.
- [ ] Phase 2 - Build the data model and card corpus pipeline.
- [ ] Phase 3 - Build authentication, accounts, and AI billing boundaries.
- [ ] Phase 4 - Build deck import and provider adapters.
- [ ] Phase 5 - Build deterministic Commander analysis.
- [ ] Phase 6 - Build OpenAI evaluation pipeline.
- [ ] Phase 7 - Build the deck evaluation UX.
- [ ] Phase 8 - Build pod evaluation and comparison.
- [ ] Phase 9 - Build the PWA experience.
- [ ] Phase 10 - Harden security, observability, and admin operations.
- [ ] Phase 11 - Ship self-hosted deployment.
- [ ] Phase 12 - Run beta, calibrate scoring, and prepare v1.

## Phase 0 - Freeze Product Charter And Repo Rules

### Objectives

- [ ] Turn the idea into stable product, architecture, and operating guidance.
- [ ] Make future agents start from the same constraints.
- [ ] Capture legal, provider, and OpenAI feasibility boundaries before code exists.

### Work Checklist

- [ ] Confirm the app name, domain, and product positioning in `README.md`.
- [ ] Add repo-local `AGENTS.md` if Stephen wants repo-specific rules beyond `/Users/sawyer/github/AGENTS.md`.
- [ ] Create `docs/analysis-rubric.md` with the first scoring rubric.
- [ ] Create `docs/provider-integrations.md` with the allowed provider integration policy.
- [ ] Create `docs/security.md` with auth, token, secret, and privacy rules.
- [ ] Create `docs/deployment.md` with the intended Ubuntu, Caddy, Docker Compose, and systemd shape.
- [ ] Add a WotC fan-content disclaimer plan.
- [ ] Decide whether the repo is private or public.
- [ ] Decide the license or explicitly mark licensing as pending.

### Exit Criteria

- [ ] A future agent can answer what Ideal Magic is, what v1 must ship, and what is out of scope.
- [ ] A future agent cannot accidentally plan around unsupported ChatGPT subscription passthrough.
- [ ] The legal and provider boundaries are written before implementation.

### Verification

- [ ] `rg -n "ChatGPT subscription|OpenAI|Moxfield|Archidekt|Fan Content|Commander" README.md BUILD.md docs`
- [ ] `git diff --check`

## Phase 1 - Scaffold The Rails Foundation

### Objectives

- [ ] Create a modern Rails app with boring local startup.
- [ ] Pin current stable Ruby and Rails versions after live verification.
- [ ] Establish quality gates before feature work.

### Work Checklist

- [ ] Re-check latest stable Ruby and Rails versions from official sources.
- [ ] Install or select the verified Ruby version locally.
- [ ] Scaffold Rails in the repo root with PostgreSQL and Tailwind CSS.
- [ ] Pin `.ruby-version`, `Gemfile`, `Gemfile.lock`, and Docker base image consistently.
- [ ] Add Hotwire, Stimulus, Tailwind, and the chosen component layer.
- [ ] Add Rails authentication generator output or an explicit auth baseline.
- [ ] Add Brakeman, RuboCop, ERB linting, and bundle audit tooling.
- [ ] Add Minitest or RSpec decision and stick to one primary test framework.
- [ ] Add root scripts for setup, lint, test, security, build, and verify.
- [ ] Add `.env.example` without secrets.
- [ ] Add health and readiness endpoints.
- [ ] Add a simple home/dashboard route that proves the app boots.

### Exit Criteria

- [ ] `bin/setup` prepares a fresh development environment.
- [ ] `bin/dev` starts the local web app.
- [ ] The root verify command runs all current checks.
- [ ] The app can connect to PostgreSQL locally.

### Verification

- [ ] `bundle exec rubocop`
- [ ] `bundle exec brakeman`
- [ ] `bin/rails test`
- [ ] `bin/rails db:prepare`
- [ ] `bin/rails assets:precompile`
- [ ] `bin/verify`

## Phase 2 - Build The Data Model And Card Corpus Pipeline

### Objectives

- [ ] Make local card data trustworthy, queryable, and refreshable.
- [ ] Keep card facts deterministic and separate from AI interpretation.
- [ ] Support Commander legality, card tags, and deck analysis features.

### Work Checklist

- [ ] Model users, decks, deck cards, commanders, provider links, card printings, oracle cards, sets, rulings, legality snapshots, analysis runs, scorecards, pod evaluations, and audit events.
- [ ] Add database indexes for deck ownership, card lookup, provider IDs, card names, oracle IDs, and analysis history.
- [ ] Build Scryfall bulk-data ingestion with polite user-agent headers and rate-limit discipline.
- [ ] Store source snapshot metadata for every card corpus refresh.
- [ ] Normalize card names, faces, color identity, mana value, type lines, oracle text, legalities, and image URIs.
- [ ] Add Commander banlist and rules snapshot storage.
- [ ] Add internal card tags for ramp, fast mana, tutors, draw, protection, removal, stack interaction, board wipes, stax, combos, graveyard use, lands, and win conditions.
- [ ] Add curated override files or admin screens for tags the card corpus cannot infer reliably.
- [ ] Add import fixtures for representative Commander decks.
- [ ] Add data refresh jobs through Solid Queue.

### Exit Criteria

- [ ] The app can answer card facts without calling OpenAI.
- [ ] Card data refreshes are repeatable and auditable.
- [ ] Commander legality checks have deterministic source data.

### Verification

- [ ] Card corpus unit tests.
- [ ] Scryfall ingestion tests against fixture payloads.
- [ ] Commander legality tests.
- [ ] Database migration reset from scratch.
- [ ] Background job smoke test for data refresh.

## Phase 3 - Build Authentication, Accounts, And AI Billing Boundaries

### Objectives

- [ ] Let users own deck history and analysis settings.
- [ ] Make OpenAI usage explicit, secure, and honest.
- [ ] Keep future auth providers replaceable.

### Work Checklist

- [ ] Implement email/password auth with secure sessions.
- [ ] Add email verification and password reset.
- [ ] Add account settings for display name, timezone, and preferred units.
- [ ] Add encrypted storage for optional user-provided OpenAI API keys.
- [ ] Add admin-owned OpenAI API key mode.
- [ ] Add per-user and global analysis quota controls.
- [ ] Add visible AI usage estimate before expensive analysis.
- [ ] Add token/cost/latency tracking per analysis run.
- [ ] Add account deletion and data export flows.
- [ ] Add provider account link placeholders without requesting third-party passwords.
- [ ] Add feature flag for future official OpenAI OAuth or ChatGPT app integration if OpenAI supports the desired flow later.

### Exit Criteria

- [ ] Users can sign up, sign in, reset passwords, and delete their account.
- [ ] AI billing mode is clear to users and operators.
- [ ] No browser can see an OpenAI API key.
- [ ] The app does not imply ChatGPT subscription passthrough is supported.

### Verification

- [ ] Auth system tests.
- [ ] Encrypted credential tests.
- [ ] Browser tests for signup, login, logout, password reset, and account deletion.
- [ ] Security review of key handling.

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
- [ ] Add duplicate card, missing card, unknown card, and commander detection workflows.
- [ ] Add manual deck edit fallback for failed imports.
- [ ] Add source attribution on every imported deck.
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
- [ ] Detect fast mana and high-power staples through tag rules.
- [ ] Estimate speed from ramp, tutors, curve, win conditions, and goldfish heuristics.
- [ ] Estimate consistency from mana, redundancy, card draw, tutors, curve, and opening-hand heuristics.
- [ ] Estimate interaction from count, type mix, mana efficiency, and coverage.
- [ ] Estimate power from deterministic feature bands before AI adjustment.
- [ ] Add simulation jobs for opening hand and early-turn probability checks where feasible.
- [ ] Store feature vectors with every analysis run.
- [ ] Create benchmark decks for precon, upgraded precon, casual, optimized, high-power, and cEDH-like ranges.

### Exit Criteria

- [ ] Every deck can receive a deterministic score draft.
- [ ] Every deterministic score exposes the facts that drove it.
- [ ] The app can run baseline analysis while OpenAI is disabled.

### Verification

- [ ] Unit tests for feature extraction.
- [ ] Commander legality regression tests.
- [ ] Benchmark deck score snapshot tests.
- [ ] Performance test for large batch analysis.

## Phase 6 - Build OpenAI Evaluation Pipeline

### Objectives

- [ ] Add AI judgment on top of deterministic facts.
- [ ] Make the model produce structured, auditable scorecards.
- [ ] Keep model cost, latency, and variance under control.

### Work Checklist

- [ ] Create an OpenAI client service for Responses API calls.
- [ ] Define JSON schema for AI scorecards.
- [ ] Define prompt versions for single-deck analysis.
- [ ] Define prompt versions for pod analysis.
- [ ] Pass deterministic feature vectors, decklist summaries, commander identity, combo candidates, and rubric text to the model.
- [ ] Instruct the model to cite only provided facts and mark uncertainty.
- [ ] Add retries, timeouts, request IDs, and failure states.
- [ ] Add moderation or abuse safeguards for user-provided deck descriptions and prompts.
- [ ] Add model selection settings with a current default and pinned snapshot option when available.
- [ ] Add low-cost and high-quality evaluation modes.
- [ ] Add evaluator tests with recorded fixtures or mocked responses.
- [ ] Add human-review admin tools for score calibration.
- [ ] Add red-team fixtures for hallucination, illegal decks, joke decks, and malformed imports.

### Exit Criteria

- [ ] AI analysis returns valid structured scorecards.
- [ ] Invalid model output is rejected and retried or surfaced as a failed run.
- [ ] Deterministic facts remain visible beside AI interpretation.
- [ ] Cost and token usage are stored per run.

### Verification

- [ ] OpenAI client unit tests.
- [ ] Schema validation tests.
- [ ] Prompt fixture tests.
- [ ] Analysis job integration test with mocked OpenAI.
- [ ] Optional live smoke test gated by `OPENAI_API_KEY`.

## Phase 7 - Build The Deck Evaluation UX

### Objectives

- [ ] Make single-deck evaluation beautiful, fast, and useful.
- [ ] Give users both a quick answer and the evidence behind it.
- [ ] Make mobile the primary table-side experience.

### Work Checklist

- [ ] Build dashboard with recent decks, analyses, imports, and queued jobs.
- [ ] Build deck detail page with commander, colors, source, card list, tags, curve, and import history.
- [ ] Build analysis run page with power, speed, interaction, and consistency scores.
- [ ] Show confidence, evidence, and improvement priorities for each score.
- [ ] Add "what changed since last analysis" diffs.
- [ ] Add recommendation sections for mana, draw, ramp, interaction, win conditions, and social fit.
- [ ] Add user feedback controls for score agreement and notes.
- [ ] Add shareable public analysis links with privacy controls.
- [ ] Add export to Markdown, text, and JSON.
- [ ] Add loading, queued, running, failed, stale, and complete states.
- [ ] Add mobile bottom navigation and desktop sidebar navigation.
- [ ] Add responsive card list controls for search, tags, categories, and role filters.

### Exit Criteria

- [ ] Users can understand a deck's strengths and weaknesses within one screen.
- [ ] Users can drill into score evidence without losing context.
- [ ] The UI remains usable on phone, tablet, and desktop widths.

### Verification

- [ ] Component tests.
- [ ] System tests for import to analysis completion.
- [ ] Playwright or Rails system screenshots for mobile and desktop.
- [ ] Accessibility checks for keyboard navigation, labels, contrast, and reduced motion.

## Phase 8 - Build Pod Evaluation And Comparison

### Objectives

- [ ] Help players compare decks before a Commander game.
- [ ] Detect mismatch, speed gaps, interaction imbalance, and likely play-pattern issues.
- [ ] Produce a useful Rule 0 conversation brief.

### Work Checklist

- [ ] Model pods, pod slots, pod decks, pod analysis runs, and shared pod links.
- [ ] Let users create a pod from 2 to 4 decks for v1.
- [ ] Support guest deck submission by public link or paste.
- [ ] Compute score spread, average, outliers, and matchup warnings.
- [ ] Detect likely archenemy decks, pubstomp risks, durdle risks, and interaction gaps.
- [ ] Generate a Rule 0 brief with power band, speed expectations, combo/stax notes, and suggested swaps.
- [ ] Show pod balance visually without hiding details.
- [ ] Add printable and shareable pod summary.
- [ ] Add "find closer decks from my library" recommendations.

### Exit Criteria

- [ ] A pod can be created, analyzed, shared, and revised.
- [ ] Mismatch warnings are specific and evidence-backed.
- [ ] Pod analysis helps players choose decks, not just assign numbers.

### Verification

- [ ] Pod model and service tests.
- [ ] Pod UI system tests.
- [ ] Benchmark pod fixture tests across balanced and mismatched pods.

## Phase 9 - Build The PWA Experience

### Objectives

- [ ] Make Ideal Magic installable and reliable on mobile and desktop.
- [ ] Support table-side use with poor network conditions.
- [ ] Keep offline behavior honest and predictable.

### Work Checklist

- [ ] Add web app manifest with proper name, short name, icons, theme color, display mode, screenshots, and app shortcuts.
- [ ] Add service worker with app-shell caching.
- [ ] Add offline fallback pages.
- [ ] Cache recent decks and recent analysis summaries for read-only offline access.
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
- [ ] PWA updates do not trap users on stale assets.

### Verification

- [ ] Lighthouse PWA checks.
- [ ] Browser install checks on desktop.
- [ ] Mobile viewport install and offline checks.
- [ ] Service worker cache update test.
- [ ] No-overlap responsive screenshots.

## Phase 10 - Harden Security, Observability, And Admin Operations

### Objectives

- [ ] Make the app safe to run publicly.
- [ ] Give Stephen operational visibility without SaaS lock-in.
- [ ] Prevent runaway AI spend and abusive traffic.

### Work Checklist

- [ ] Add rate limiting for auth, imports, analysis creation, and public share pages.
- [ ] Add CSRF, secure cookie, CORS, CSP, and security header review.
- [ ] Add audit events for auth, import, analysis, provider refresh, key changes, and admin actions.
- [ ] Add admin dashboard for users, jobs, imports, analysis failures, provider health, and AI spend.
- [ ] Add structured logs with request IDs.
- [ ] Add error reporting route or local log workflow.
- [ ] Add OpenTelemetry-compatible instrumentation if it earns the complexity.
- [ ] Add database backup and restore scripts.
- [ ] Add abuse controls for public imports and share links.
- [ ] Add privacy controls for deck visibility and analysis sharing.
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

## Phase 11 - Ship Self-Hosted Deployment

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

## Phase 12 - Run Beta, Calibrate Scoring, And Prepare V1

### Objectives

- [ ] Validate that scores match real Commander expectations.
- [ ] Improve the rubric from feedback without losing explainability.
- [ ] Ship a coherent v1 instead of endless feature creep.

### Work Checklist

- [ ] Recruit beta users with different Commander metas.
- [ ] Collect score disagreement feedback.
- [ ] Create calibration decks for each power band.
- [ ] Tune deterministic scoring weights.
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

Inputs include score spread, speed spread, combo and stax profile, interaction distribution, win-condition clarity, and social friction flags.

## V1 Non-Goals

- [ ] Native iOS or Android apps.
- [ ] Full rules-engine gameplay simulation.
- [ ] Private Archidekt or Moxfield account sync without official auth.
- [ ] Charging for WotC IP-backed fan content without legal review.
- [ ] Replacing Scryfall as the card data source.
- [ ] Building a Discord bot before the web app is useful.
- [ ] Building trading, collection finance, or marketplace features.
- [ ] Supporting every MTG format before Commander is excellent.

## Future Feature Backlog

- [ ] ChatGPT app or GPT Action that can analyze a deck from inside ChatGPT.
- [ ] Browser share target for deck URLs.
- [ ] Deck improvement simulator with budget and salt constraints.
- [ ] Meta profiles for specific playgroups.
- [ ] Collection-aware upgrade recommendations.
- [ ] Commander recommendation engine from user preferences.
- [ ] Local group night mode with QR code deck submission.
- [ ] Public deck gallery and analysis leaderboard.
- [ ] Optional Discord bot for pod checks.
- [ ] Optional email summaries for deck changes and stale imports.
- [ ] Human-curated archetype taxonomy.
- [ ] Calibration mode where trusted users help tune scoring.
