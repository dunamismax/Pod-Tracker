# BUILD.md

Active build manual for Ideal Magic. Reading this plus `AGENTS.md` and `README.md` is enough context to ship.

Last updated: 2026-05-07 (Slice 11 closed - production Codex auth cutover)

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
- **Codex account-auth:** encrypted credential storage, device-code login as the production-safe hosted path, browser login labeled as same-machine-only, refresh-status, remote sign-out, per-user/global quota policy with rate-limit display. The live Codex App Server JSON-RPC transport is wired behind `CODEX_APP_SERVER_ENABLED`; default remains fail-closed with `NullTransport`. The deck show page surfaces a "Connect ChatGPT / Codex account" CTA when no account is linked so the path to AI evaluation is one click from the deck. Single-deck AI evaluation now runs on prompt `deck-eval-v2` and schema `deck-evaluation-v2` — the LLM is fed the long-form bracket rules text, the canonical Game Changers list, and the current Commander banlist, then asked to make the bracket call and the six 0-10 axis calls itself; once a v2 run succeeds it becomes the authoritative deck evaluation on the show page (deterministic stays as a collapsible preliminary read). Pod evaluation continues to run on the v1 augmentation schema.
- **Provider link placeholders** for Archidekt and Moxfield public profile URLs (no third-party password collection).
- **Card corpus:** Scryfall bulk-data ingestion, Commander rules/banlist snapshot, internal tag taxonomy with curated salt/social-friction overrides, deterministic legality checker, daily Solid Queue refresh job.
- **Deck import:** pasted text, uploaded text file, public Archidekt URL, public Moxfield URL. Imports surface unparsed lines, source attribution, audit events.
- **Deterministic deck analysis:** every import runs feature extraction, Commander legality, and a six-axis scorecard (Power, Speed, Interaction, Consistency, Salt, Social Friction). Deck show page renders per-score evidence drawers, legality result, tuning recommendations, and optional Codex AI augmentation beside the deterministic evidence.
- **Collection:** signed-in users can import owned cards from pasted text, uploaded text, or simple CSV, manually add/edit/remove card quantities, review unresolved rows, see owned-vs-missing deck gaps on each deck page, review demand pressure across decks, and see whether tuning suggestions have matching owned options or likely need acquisition.
- **Pods (2–4 decks):** build a pod from your own decks, optionally including one guest deck via pasted decklist or public Archidekt / Moxfield URL. Pods get per-axis spread/average/outliers, archenemy/pubstomp/durdle warnings, a Rule 0 brief (power band, tempo, combo/stax notes, salt/friction notes), and per-deck swap suggestions. Mobile-readable and printable show page. Opt-in revocable public share link. Guest decks live only with the pod and are removed when the pod is removed.
- **Game-night sessions:** signed-in users can create a session at `/sessions`, save date/location/notes, create or reuse user-owned players, and check each player in with one owned deck of the night. Sessions suggest pod seating from the checked-in roster, allow manual pod/seat overrides, snapshot each seated deck's name, commanders, deck timestamp, card count, and deterministic analysis, record pod results, and render a session summary.
- **Matchup journal and meta:** signed-in users can create, search, edit, and remove matchup notes tied to a deck, optional commander, opponent, saved pod, and/or game-night session pod number. Session seating surfaces recent prior notes matching the seated decks, commanders, or opponents. Completed session results now feed post-game prompts, per-deck record/win-rate/average-turn summaries, revision-level result history, and commander meta tables with sample-size labels.
- **Seeded users:** admin (`stephenvsawyer@gmail.com`, password from `IDEAL_MAGIC_ADMIN_PASSWORD`) and demo (`demo@demo.com` / `demo1234`). `bin/rails demo:reset` factory-resets the demo account.
- **PWA shell:** `/manifest.json` advertises Ideal Magic with maskable + 192/512 icon variants and Decks/Pods/Sessions shortcuts; `/service-worker.js` cache-firsts the app shell, network-firsts recently visited deck/pod/session pages so they stay readable offline, evicts old caches by asset version + app revision on activate, and a `pwa-update` Stimulus controller prompts a reload when a new worker is waiting.
- **Production:** live at https://ideal-magic.com via Caddy + systemd + host PostgreSQL. `bin/redeploy` is the iteration loop.

## Phase Status Summary

Slice 11 is closed: the Codex App Server transport is multi-tenant and production-wired. Every Ideal Magic user gets their own `CODEX_HOME` under `CODEX_HOME_ROOT/<user.id>/`, mode 0700, materialized by `Codex::UserHome.ensure!(user)` on first login with `cli_auth_credentials_store = "file"` written to `config.toml` so Codex stores credentials in that user's `auth.json`. `Codex::AppServerClient.for(user)` constructs a fresh client per request whose `StdioTransport` spawns codex with that user's `CODEX_HOME` (and an explicit allowlisted env that does not forward Rails secrets). `Codex::AccountConnections` and `Codex::EvaluationRunner` build clients per-user, so two concurrent evaluations for two different users get two distinct transports — they cannot cross streams. Logout, codex-account disconnect, and account deletion all `UserHome.purge!` the user's directory. `poll_chatgpt_login` no longer reads rate limits before `account/read` reports an account, so in-progress sign-ins are not marked failed by "codex account authentication required to read rate limits." Device-code login is the production-safe path on ideal-magic.com; browser login remains available but is labeled same-machine-only because the App Server browser flow redirects to localhost on the app-server host. Production reads `ACTIVE_RECORD_ENCRYPTION_*` keys from `/etc/ideal-magic-web/env` so `CodexAccount#encrypted_credential_payload` can persist after login. The live unit has `CODEX_HOME_ROOT=/var/lib/ideal-magic/codex`, `ProtectHome=read-only`, `ReadWritePaths=/var/lib/ideal-magic/codex`, and that root exists as `sawyer:sawyer` mode 0700. Stephen still needs to re-run "Connect ChatGPT / Codex account" once to materialize his per-user CODEX_HOME (`/home/sawyer/.codex` is not moved or read by the service).

Slice 10 is open: deck AI evaluation has moved from a deterministic-augmentation contract to a deckcheck-style authoritative read. Prompt `deck-eval-v2` embeds the long-form Commander Brackets rules text, the full Game Changers list, the current banlist, the six-axis power-band rubric, and the deck name + decklist; the LLM produces the bracket call, sub-band, and six 0-10 axes itself, validated by `Codex::DeckEvaluationValidator` against schema `deck-evaluation-v2`; the deck show page surfaces the AI evaluation as the canonical bracket and power-band display once a v2 run succeeds, with the deterministic numbers collapsed into a "preliminary read" disclosure. The deck show page also surfaces a one-click "Connect ChatGPT / Codex account" CTA when no Codex account is linked so the AI path is reachable without leaving the deck. Pod evaluation continues to run on the v1 augmentation schema.

Slice 9 is closed: deck pages offer plain-text/CSV/JSON decklist downloads and Markdown/JSON deterministic-analysis downloads; the JSON account export covers collection cards + import history, game-night players/decks/seats/results, and matchup notes; decks have opt-in revocable share tokens that expose a read-only public deck page (`/d/:token`) plus matching token-gated decklist and analysis downloads (with playgroup notes, AI runs, performance, and collection data deliberately withheld); `bin/backup_db` + `bin/restore_db_drill` plus the canonical `config/systemd/ideal-magic-backup.{service,timer}` units now drive daily `pg_dump` backups for all four production databases with a documented restore drill at `docs/runbooks/postgres-backups.md`; and the daily Scryfall card-corpus refresh job has an operator runbook at `docs/runbooks/scryfall-corpus-refresh.md`. Slice 8 remains delivered: PWA shell + update banner, mobile bottom nav, deck-index filters, and the global "offline pause" banner that disables submit on every mutating form.

## Current Repo Truth

The Codex App Server transport is multi-tenant: per-user `CODEX_HOME` directories live under `CODEX_HOME_ROOT` (default `/var/lib/ideal-magic/codex` in production, `tmp/codex_home` in dev/test) at `<root>/<user.id>/` mode 0700. `Codex::UserHome` owns directory lifecycle (`ensure!`, `has_auth?`, `purge!`) and writes `config.toml` mode 0600 with `cli_auth_credentials_store = "file"` so Codex stores credentials in the user's `auth.json`, not a shared keyring. `Codex::AppServerClient.for(user)` constructs a fresh client per request whose `StdioTransport` spawns the codex CLI with `CODEX_HOME=<user dir>` plus an explicit env allowlist (`PATH`, `HOME`, `LANG`, `LC_ALL`, `USER`) — Rails secrets are never forwarded into the child process. `Codex::AccountConnections.for(user)` and `Codex::EvaluationRunner.run!` both resolve their client through `build_client_for(user)`; the legacy `client_factory` setter still works for tests (zero-arity returns one client; one-arity is invoked per user). `AppServerClient#get_auth_status` reads rate limits only after `account/read` returns an account, preventing unauthenticated rate-limit reads during an in-progress login. Disconnect/logout/account-deletion call `UserHome.purge!`. `AccountConnections#refresh_status` short-circuits to `disconnected` when `CODEX_HOME/auth.json` is missing on disk so the DB and disk truth never disagree. The production systemd unit has `CODEX_HOME_ROOT=/var/lib/ideal-magic/codex`, `ProtectHome=read-only`, and `ReadWritePaths=/var/lib/ideal-magic/codex`; the root exists as `sawyer:sawyer` mode 0700.

Single-deck AI evaluation now uses prompt `deck-eval-v2` (`Codex::DeckEvaluationPrompt`) and response schema `deck-evaluation-v2` (`Codex::DeckEvaluationSchema` + `Codex::DeckEvaluationValidator`). The prompt is built from `Codex::BracketBriefing`, which embeds the Commander Brackets long-form rules text, the canonical Game Changers list (loaded from `db/seeds/commander/brackets/game_changers.json`), the Commander banlist (from `db/seeds/commander/legality_snapshots/current.json`), and the six-axis 0-10 power-band rubric. The LLM is asked to make the bracket call, sub-band call, and the six 0-10 axis calls itself; the deterministic feature vector is included only as a sanity check. `Decks::AiEvaluationPresenter.for(latest_ai_run)` returns the AI bracket, sub-band, restrictions, axes, friction drivers, talking points, and recommendations to the deck show page when a v2 run has succeeded — the new `decks/_ai_analysis.html.erb` partial renders that as the canonical deck evaluation, while the existing deterministic `decks/_analysis.html.erb` surface is collapsed under a "preliminary deterministic read" disclosure. When no Codex account is connected, the `codex/_ai_evaluation` partial replaces the run button with a direct "Connect ChatGPT / Codex account" CTA pointing at `new_account_codex_login_path` so the AI path is one click from the deck. Legality remains source-backed deterministic; the AI is only allowed to flag legality concerns under an optional `legality_review` block, never to override the rules engine. Pod evaluation continues to use the v1 `Codex::ScorecardResponseSchema` augmentation contract; the `EvaluationRunner` selects the correct validator per target.

Ideal Magic ships an installable PWA: `/manifest.json` and `/service-worker.js` are served from `app/views/pwa/`, the layout links the manifest, declares `theme-color`, `apple-mobile-web-app-*` metadata and a maskable icon, and a Stimulus controller registers the worker, listens for waiting updates, and surfaces a reload banner so users are not trapped on stale assets. The service worker keeps the app shell (root, manifest, icon, `/assets/*`) cache-first with background revalidation, network-firsts the allowlisted `/app`, `/decks`, `/pods`, and `/sessions` navigations into a cache so a recently visited page renders offline, and is keyed by `Rails.application.config.assets.version` plus the app revision so deploys evict old caches. Authenticated phone-sized viewports render a fixed five-up bottom nav (Decks, Pods, Sessions, Journal, Collection) keyed off `ApplicationController#mobile_nav_section`. The deck index renders a search box plus bracket and status filters that compose against `current_user.decks`. A global `offline` Stimulus controller listens for `online`/`offline` events, exposes a top-of-viewport "anything you submit is paused" banner, and disables `[type=submit]` controls inside any `form[data-offline-disable]` — wired into deck import, AI evaluation, pod creation, session creation/seating/result submission, matchup-note CRUD, collection add, and collection import forms so the UI never claims a server-side write happened while disconnected. Deck show pages now expose plain-text/CSV/JSON decklist downloads and Markdown/JSON deterministic-analysis downloads (`Decks::Exporter`, `Decks::AnalysisExporter`, served at `GET /decks/:id/export.{text,csv,json}` and `GET /decks/:id/analysis.{markdown,json}`). Decks also carry opt-in revocable share tokens (`decks.share_token` / `shared_at` / `share_revoked_at`, mirrored from the pod model) issued and revoked through `DeckSharesController`, surfaced on the deck show page, and consumed by `PublicDecksController` at `GET /d/:token`, `GET /d/:token/export.{text,csv,json}`, and `GET /d/:token/analysis.{markdown,json}` — the public surface renders the decklist, commanders, deterministic six-axis analysis, bracket placement, legality, and tuning suggestions, but never the AI run, table-performance summary, collection fit, matchup notes, audit history, or any other playgroup-tied data. The signed-in account export (`Accounts::Exporter`, schema v2) ships full account state — account/codex/provider links plus decks, analysis runs, pods, collection cards + import history, game nights with players/decks/seats/results, matchup notes, and audit events. Codex-backed deck and pod AI evaluations remain queue-able from the show pages, gate through the existing quota policy, persist prompt/input/output/model/latency/rate-limit replay metadata on `AnalysisRun`, and render validated AI summaries, cited adjustments, friction drivers, Rule 0 talking points, and recommendations beside deterministic evidence. The default Codex transport still fails closed unless `CODEX_APP_SERVER_ENABLED=true` is configured.

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
- [x] Build a pod from 2–4 of the user's decks. Allow a guest deck via paste or public URL.
- [x] Pod analysis: per-axis spread, average, outliers, archenemy/pubstomp/durdle warnings, salt and social-friction spread.
- [x] Rule 0 brief: power band, speed expectations, combo/stax notes, salt/friction notes, suggested swaps.
- [x] Pod show page that's mobile-readable and printable.
- [x] Public pod share link, opt-in, revocable.
- [x] Tests: pod service tests across balanced and mismatched fixtures; system test for create → analyze → share.

### Slice 3 — Commander Brackets + public marketing site

The 0–10 power scale was the v0 framing. The official Commander Brackets system (Wizards, beta-style, last updated 2026-02-09) replaces it as Ideal Magic's primary axis for deck intent and Rule 0 conversation. Brackets 1–5 (Exhibition, Core, Upgraded, Optimized, cEDH) carry restrictions, Game Changers, turn expectations, and a shared vocabulary that 1–10 never had.

Power, speed, interaction, consistency, salt, and friction stay — they sub-band a deck *inside* its bracket (low-power Bracket 3 vs high-power Bracket 3, etc.) and explain Rule 0 friction.

This slice also opens the site up: today every page demands a login. Going forward, ideal-magic.com has a public marketing surface (bracket education, About, FAQ, fan-content notice) that anyone can read without signing in. Pods, decks, sessions, and anything tied to a user account stay behind auth.

The bracket pages should be the best-on-the-internet explanation of the system — long-form, screenshot-friendly, link-shareable, and grounded in the actual Wizards rules, not paraphrase. Treat the writing surface as a deliverable on par with the code.

#### Bracket data + scoring

- [x] Land the canonical Game Changers list (53 cards as of 2026-02-09, including Farewell + Biorhythm) as deterministic source data under `db/seeds/commander/brackets/`. Version it, refresh it on update, and key it by normalized card name.
- [x] Land the canonical Commander banned list refresh: Biorhythm is unbanned (now on the Game Changers list), Lutri is companion-only-banned (legal as a commander or deck card; companions are not assigned in Commander format, so it is omitted from `banned_names`), and the legality snapshot is dated 2026-02-09 with `source_checked_on` 2026-05-05.
- [~] Tag the curated overrides for mass land denial, extra-turn cards, and known two-card combo halves. (Two-card combo catalog landed at `db/seeds/commander/brackets/two_card_combos.json`. MLD/extra-turn tags already live in `card_tags/overrides.json`. Wider combo coverage still open.)
- [x] `Decks::BracketEvaluator` service: returns `{ bracket: 1..5, label, sub_band: "low|mid|high", expected_min_turn, restrictions: [...met/violated...], game_changers: [{name, category}], evidence, headline }` from a feature vector + decklist + scorecard.
- [x] Bracket placement rules encode the published gates: Bracket 1 (no GCs, no MLD, no extra turns, no two-card game-enders, theme-first), Bracket 2 (no GCs, no MLD, no chained extra turns, no two-card game-enders), Bracket 3 (≤3 GCs, no MLD, no chained extra turns, no two-card combo before turn 6), Bracket 4 (banned list only, optimized, non-cEDH intent), Bracket 5 (cEDH metagame intent).
- [x] Sub-band uses the existing power/speed scorecard plus combo compactness so a deck can read as "low-power Bracket 3" or "high-power Bracket 3" without re-bucketing into another bracket.
- [x] Migration: add `bracket`, `bracket_sub_band`, `bracket_payload` to `scorecards`.
- [x] `Decks::Analyzer` writes the bracket alongside the existing six scores. Bracket is the headline; the 1–10 axes become sub-band evidence.
- [x] Tests: `BracketEvaluator` unit tests across the five fixture archetypes plus targeted cases (combo-only, MLD-only, single GC vs four GCs, chained extra turns vs single splashy turn).
- [x] Update `Decks::BenchmarkScoringTest` to assert bracket placement across all five bracket bands, including the new `cedh_tymna_thrasios_thoracle` Partner fixture (Tymna + Thrasios Thoracle/Consultation shell) which locks in Bracket 5 with the Game Changer count + immediate-win combo pair surfaced through the bracket payload.

#### Pod analysis with brackets

- [x] `Pods::Analyzer` aggregates bracket spread across slots (min/max/distinct), plus existing axis aggregates.
- [x] `Pods::WarningGenerator` adds a bracket-mismatch warning when slots span 2+ brackets, replacing/augmenting today's archenemy/pubstomp signals where bracket gap is the real story.
- [x] `Pods::RuleZeroBrief` is rewritten around the bracket vocabulary: headline is the pod bracket (or "mixed Brackets X–Y"), expected minimum turn, GC count across the pod, MLD/extra-turn/combo disclosure prompts, and an explicit Rule 0 prompt template.
- [x] Pod show page surfaces each slot's bracket badge, the pod bracket headline, and a copyable Rule 0 prompt formatted for pasting into Discord / chat.
- [x] Tests: `Pods::AnalyzerTest` asserts bracket spread + `bracket_mismatch` warning across a Bracket 2 → Bracket 5 mismatched four-pod, and a balanced Bracket 2 three-pod produces a single-bracket headline with no `bracket_mismatch` warning.

#### Deck + pod UI

- [x] Deck show page: bracket badge + "what this means" link, sub-band line, GC list (with categories), restrictions met/violated, expected minimum turn, 1–10 axes demoted to a collapsed "Sub-band evidence" section.
- [x] Pod show page: pod bracket headline, per-slot bracket badges, copyable pregame template populated from the deck data.
- [x] Public pod share page mirrors the same surface (read-only) — it renders the same `pods/_analysis.html.erb` partial.
- [x] Mobile-first layout for badges + restrictions; the bracket reads in one glance from across the table.

#### Public marketing site

The site no longer redirects every visitor to `/session/new`. Public surface lives under a dedicated `PublicController` with the existing application layout, which now adapts its header and footer for signed-in vs anonymous visitors.

- [~] Marketing layout — the existing `application.html.erb` was rewritten with a public-aware header (logo, nav, sign-in/sign-up vs Open-app CTAs) and a fan-content footer (GitHub, privacy, terms). A separate `layouts/marketing.html.erb` was not needed; if/when the marketing surface diverges further, split it.
- [x] Routes: `root` resolves to `public#home` for everyone (signed-in users see the same page with an "Open app" CTA); the dashboard moved to `/app`. `Authentication#require_authentication` remains a global before-action with `allow_unauthenticated_access` opt-out per public controller.
- [x] `/` — landing page: one-liner pitch, "what brackets are", how Ideal Magic uses them, primary CTAs (Read about brackets / Try the demo / Sign up), Game Changers + pregame template teasers.
- [x] `/brackets` — the headline bracket explanation page. Long-form, written from the supplied source. Sections: what brackets are, the four axes, each bracket in depth (1 Exhibition through 5 cEDH) with mindset / restrictions / right-vs-wrong reasons, mass land denial, extra turns, two-card combos, tutors, the Game Changers list (rendered from the canonical data file with categories), the current banned list (rendered from the legality snapshot), classification decision tree, pregame template, common misclassifications, final summary table.
- [x] `/brackets/game-changers` — dedicated page rendering the canonical GC list grouped by category.
- [x] `/brackets/pregame-template` — the copy-pasteable pregame Rule 0 template with worked examples (Bracket 1 Weatherlight Crew, Bracket 2 Ghyrson Starn, Bracket 3 Voja, Bracket 4 Pantlaza, Bracket 5 Thoracle).
- [x] `/about` — what Ideal Magic is, who builds it, fan-content disclaimer, link to GitHub.
- [x] `/privacy` and `/terms` so footer links resolve.
- [x] Meta tags + Open Graph on every public page so shared links render well. Per-page `meta_description`, `og:title`/`og:description`/`og:site_name`/`og:url`/`og:image`/`og:image:alt`, full `twitter:` cards (`twitter:title`/`twitter:description`/`twitter:image`), `<link rel="canonical">`, site-wide `Organization` + `WebSite` JSON-LD, `BreadcrumbList` on the bracket sub-pages, `Article` on `/brackets`, plus `/sitemap.xml` and a sitemap-aware `robots.txt`.
- [x] Tests: request specs for every public page; assert no auth redirect, assert canonical content present.

#### Auth gating + navigation

- [x] Public controllers (home, brackets, game changers, pregame template, about, privacy, terms) explicitly allow anonymous via `allow_unauthenticated_access`. The remaining controllers stay behind the global `require_authentication` before-action.
- [x] Header shows "Sign in" / "Create account" when anonymous and "Open app" + "Sign out" when signed in.
- [x] No auth-required page leaks user data into the public surface.
- [x] Optional: a "Site" link inside the authenticated app surface back to the public marketing surface. (The signed-in header now shows Decks / Pods / Sessions / Site.)

#### Docs + content

- [x] Update `docs/analysis-rubric.md`: replace 0–100 power band table with the bracket framing; document brackets as the primary axis and the six 0–10 axes as sub-band evidence.
- [x] Update `README.md`: lead with brackets, demote 0–10 power language. Mention the public site surface.
- [x] Confirm fan-content notice appears on the public marketing footer.
- [x] Add `docs/public-site.md` covering routes, layout, content edit workflow, and SEO baseline.

---

### Slice 4 — Game-night sessions and result recording

- [x] Session model: `GameNight`, `Player`, `GameNightPlayer`, `GameNightDeck`, `GameNightPodSeat`, and `GameNightPodResult`. Product copy still says "sessions"; the model is named `GameNight` to avoid colliding with auth `Session`. Players are user-owned named entities — no public ranking surface.
- [x] Create a session (date, location, notes) and check players in with their deck of the night. `/sessions/new` creates/reuses player records and snapshots deck name + commanders.
- [x] Suggest pod seating from checked-in players; allow manual overrides. `GameNights::SeatingSuggester` balances bracket/power when deterministic analysis exists; the session show form lets users edit pod and seat numbers before saving.
- [x] Record results: winner, draw state, turns, win condition, free-text notes.
- [x] Snapshot the deck revision and analysis used for each pod seat so meta history is honest later. Seat snapshots store deck name, commanders, deck `updated_at`, deck card count, latest deterministic analysis run, bracket, and six-axis scores.
- [x] Session summary page with the night's pods, results, and links back to deck/analysis snapshots.
- [x] Tests: session workflow system test from create → check-in → seat → record → summary.

### Slice 5 — Collection and ownership

- [x] Collection model: `CollectionCard`, `CollectionImport`, `UnresolvedEntry`.
- [x] Pasted and uploaded collection import (text + simple CSV).
- [x] Manual add / edit / remove / quantity adjust.
- [x] Unresolved-card review for ambiguous names.
- [x] Owned vs missing per deck on the deck show page.
- [x] Demand pressure: which missing cards matter across multiple decks.
- [x] Recommendations distinguish "you already own this" from "you'd have to buy it." No price/marketplace flow.
- [x] Tests: import parser, ownership service, system test for collection → deck gaps.

### Slice 6 — Matchup journal and meta trends

- [x] Matchup note model: belongs to user, links to deck, commander, opponent (player), pod, session. Tags + free text.
- [x] Note CRUD with search by tag, deck, commander, player, pod, session.
- [x] Pre-game context surface: when seating a pod, show prior notes for those decks/commanders/opponents.
- [x] Post-game prompt for wins/losses/draws/short games/dead draws/missing cards.
- [x] Deck performance: games, wins, draws, win rate with sample-size confidence, average turns, last played.
- [x] Commander meta: appearances, wins, win rate, recent trend. Sample size visible; never pretend thin data is certain.
- [x] Revision performance: connect deck revisions to results so "what changed since this deck last won" is answerable.
- [x] Tests: matchup search, meta service against fixture sessions.

### Slice 7 — Codex AI evaluation as augmentation

The v1 differentiator. Build it on top of deterministic analysis, not as a replacement.

- [x] Implement a real Codex App Server JSON-RPC transport against the documented account-auth surface. Replace `NullTransport` with the live client behind a feature flag. (`CODEX_APP_SERVER_ENABLED=true` enables the stdio transport using `CODEX_APP_SERVER_COMMAND`, defaulting to `codex app-server`; the client normalizes documented `account/login/start`, `account/read`, `account/rateLimits/read`, `account/login/cancel`, and `account/logout` calls.)
- [x] JSON schema for AI scorecards: power/speed/interaction/consistency/salt/social-friction adjustments, friction drivers, Rule 0 talking points. Cite deterministic facts; mark uncertainty. (`Codex::ScorecardResponseSchema` + validator landed with required fact refs and uncertainty arrays.)
- [x] Single-deck prompt v1: pass the deterministic feature vector, decklist, commander, combo candidates, salt/friction evidence, and rubric. Ask for adjustments + explanations, not raw scores. (`Codex::DeckEvaluationPrompt` builds versioned payloads with deterministic fact IDs.)
- [x] Pod prompt v1: same shape, pod-aware. (`Codex::PodEvaluationPrompt` builds pod-context payloads from `PodAnalysisRun` snapshots.)
- [x] Background job that runs evaluation against a quota-checked Codex account; surfaces queued / running / failed / stale states on the deck and pod pages. (`CodexEvaluationJob` + `Codex::EvaluationRunner` create queued AI `AnalysisRun` records for decks/pods, run them through the App Server client, and show the run state on deck/pod pages.)
- [x] Replayable runs: store prompt version, model, inputs, outputs, latency, and rate-limit snapshot per `AnalysisRun`. (`analysis_runs.pod_id` + `prompt_version` landed; AI request/response JSON snapshots now hold target metadata, prompt input/messages, raw text, validated response, thread/turn metadata, and rate-limit snapshots.)
- [x] Recorded-fixture tests for the prompt → response → schema validation path. No live calls in CI. (`test/fixtures/files/codex_scorecard_response_v1.json` validates against the schema and cites fact IDs provided by the deck prompt.)
- [x] AI explanations render alongside deterministic evidence; the deterministic numbers stay visible. (Deck and pod show pages now render Codex summaries, cited score adjustments, friction drivers, Rule 0 talking points, and recommendations after the deterministic analysis sections.)

### Slice 8 — PWA and table-side polish

- [x] Web app manifest, service worker, app-shell cache. (`/manifest.json` + `/service-worker.js` rendered via `rails/pwa#manifest` and `rails/pwa#service_worker`; the SW cache-firsts the root, manifest, icon, and `/assets/*` so the shell loads when the network is hostile.)
- [x] Recent decks and analyses cached for read-only offline access. (Navigation requests to `/app`, `/decks`, `/decks/:id`, `/pods`, `/pods/:id`, `/sessions`, `/sessions/:id` are network-first with a cache fallback that tags the response with `X-Ideal-Magic-Offline: 1`.)
- [x] iOS home-screen + Android maskable icon coverage. (Layout sets `apple-mobile-web-app-capable`, `apple-mobile-web-app-title`, `apple-mobile-web-app-status-bar-style`, `theme-color`, `apple-touch-icon`; manifest declares both `any` and `maskable` icon variants in 192/512.)
- [x] Cache versioning and an update prompt that doesn't trap users on stale assets. (Cache name is keyed by `Rails.application.config.assets.version` plus the app revision; activate evicts non-matching `ideal-magic-*` caches; the `pwa-update` Stimulus controller surfaces a "Reload" banner when a new worker is waiting and triggers `SKIP_WAITING` so the page reloads onto fresh assets.)
- [~] Mobile bottom nav, desktop sidebar nav, responsive deck-list controls (search, tag filter, role filter). (Mobile bottom nav for authenticated users landed via `app/views/shared/_mobile_bottom_nav.html.erb` with active-section highlighting wired through `ApplicationController#mobile_nav_section`. Deck index now has a search-by-name/commander box plus bracket and status filters via `DecksController#index`. Desktop sidebar nav is deliberately deferred — the existing top nav still works at sm+; revisit if/when the top bar gets crowded. The "tag filter / role filter" wording was speculative; bracket + status are the deck-level filters that map to existing data, and a card-tag filter would need a different UX surface.)
- [x] Honest offline states: never pretend AI runs, imports, or new results have reached the server while offline. (`offline_controller.js` listens to `online`/`offline` events, surfaces a top-of-viewport banner that says "Anything you submit is paused until you reconnect — nothing has reached the server yet," and disables `[type=submit]` buttons inside any `form[data-offline-disable]`. Wired into deck import, AI evaluation buttons, pod creation, session creation, session seating, session result submission, matchup-note CRUD, collection add and collection import forms.)

### Slice 10 — AI-authoritative deck evaluation (deckcheck-style)

The user-visible jump from "deterministic plus optional Codex augmentation" to "Codex is the bracket and power-band authority" once an evaluation has run.

- [x] Bracket briefing service (`Codex::BracketBriefing`) packages the Commander Brackets long-form rules, the canonical Game Changers list, the current Commander banlist, and the six-axis 0-10 anchor bands as deterministic prompt context.
- [x] New deck-evaluation schema + validator (`Codex::DeckEvaluationSchema` / `Codex::DeckEvaluationValidator`, version `deck-evaluation-v2`) where the AI returns absolute bracket, sub-band, restrictions, the six axes (0-10), drivers, talking points, recommendations, and an optional legality review.
- [x] `Codex::DeckEvaluationPrompt` rewritten to prompt-version `deck-eval-v2` — feeds bracket briefing + deck name + decklist + deterministic signals + response contract; `Codex::EvaluationRunner` validates deck runs with the new validator while pod runs stay on the v1 augmentation schema.
- [x] Deck show page surfaces the AI evaluation as authoritative once a successful v2 run is recorded (`decks/_ai_analysis.html.erb` + `Decks::AiEvaluationPresenter`). Deterministic stays as a collapsed "preliminary read." Legality remains source-backed deterministic.
- [x] AI evaluation panel surfaces a "Connect ChatGPT / Codex account" CTA when no account is linked, so the AI path is one click from the deck.
- [x] Tests: `Codex::DeckEvaluationValidatorTest`, expanded `Codex::EvaluationPromptTest`, `Codex::EvaluationRunnerTest` against the v2 fixture, `Decks::AiEvaluationPresenterTest`, `DecksControllerTest` coverage for the connect CTA and AI-authoritative rendering.
- [ ] Pod evaluation prompt + schema upgrade to v2-equivalent so AI is also authoritative for pod bracket spread and Rule 0 brief. (Deferred — pod prompt currently still surfaces v1 augmentation only.)
- [ ] Public deck share page mirrors AI evaluation when a deck has a successful AI run. (Deferred — current public surface deliberately omits AI runs; revisit if/when sharing AI verdicts becomes a use case.)
- [ ] AI-aware analysis exports (Markdown/JSON include AI bracket + axes when present). (Deferred — current exports remain deterministic.)

### Slice 11 — Per-user Codex tenancy

Make Codex genuinely multi-tenant so each Ideal Magic user authenticates their own ChatGPT subscription and AI evaluations always run against the right user's account. Without this, the on-disk `~/.codex/auth.json` was effectively single-tenant: whichever user most recently completed "Connect Codex" overwrote it for everyone.

- [x] `Codex::UserHome` service: `root_path` (from `CODEX_HOME_ROOT`, dev fallback `tmp/codex_home`), `path_for(user)`, `ensure!(user)` mkdir 0700, `has_auth?(user)`, `purge!(user)`. Unit-tested.
- [x] `Codex::AppServerClient::StdioTransport` accepts an `env:` kwarg and passes it to `Open3.popen3` so the child codex process inherits a controlled env. Allowlist-only forwarding from the parent (`PATH`, `HOME`, `LANG`, `LC_ALL`, `USER`) so Rails secrets do not leak into the child.
- [x] `Codex::AppServerClient.for(user)` constructs a fresh client per request bound to the user's `CODEX_HOME`. `from_environment(env:, codex_home:)` is the lower-level entry point.
- [x] `Codex::AccountConnections.for(user)` builds the per-user client itself; `client_factory` test override now supports both zero-arity and one-arity callables. `logout` (and the bare disconnect controller) call `UserHome.purge!`. `refresh_status` flips the local row to `disconnected` when `CODEX_HOME/auth.json` is missing on disk.
- [x] `Codex::EvaluationRunner.run!` resolves the client via `build_client_for(analysis_run.user)`. Two concurrent runs for two different users get two distinct transports.
- [x] Account deletion (`AccountDeletionsController`) purges the user's CODEX_HOME before destroying the row.
- [x] Tests: `UserHomeTest`, expanded `AppServerClientTest` (env kwarg flows into popen3, secret allowlist), `AccountConnectionsTest` (logout purges, refresh_status disconnects on missing auth), `EvaluationRunnerTest` (per-user client construction for concurrent runs).
- [x] Docs: `.env.example`, `docs/deployment.md`, `BUILD.md`, `README.md` reflect the per-user CODEX_HOME design.
- [x] Production wiring: `CODEX_HOME_ROOT=/var/lib/ideal-magic/codex` plus `ReadWritePaths=/var/lib/ideal-magic/codex` in the systemd unit, mkdir/chown/chmod 0700, daemon-reload + restart. Verified live unit has `CODEX_HOME_ROOT`, `ProtectHome=read-only`, and `ReadWritePaths=/var/lib/ideal-magic/codex`; the root exists as `sawyer:sawyer` mode 0700. Stephen re-runs "Connect ChatGPT / Codex account" once after the cutover to materialize his per-user CODEX_HOME; `/home/sawyer/.codex` is not migrated. Browser sign-in is labeled same-machine-only; device-code sign-in is the hosted production path.

### Slice 9 — Exports, share links, and operational polish

- [x] Deck export to plain text, CSV, and JSON from the deck show page. (`Decks::Exporter` + `DeckExportsController` route at `GET /decks/:id/export.{text,csv,json}`; deck show page renders the download links.)
- [x] Analysis export to Markdown and JSON. (`Decks::AnalysisExporter` + `DeckAnalysisExportsController` route at `GET /decks/:id/analysis.{markdown,json}`; markdown variant covers the bracket headline, sub-band scores, restrictions, legality, and suggestions; JSON variant ships the full payload with the latest deterministic run.)
- [x] Public deck and analysis share links with opt-in revocation; safe defaults (no playgroup notes leak). (`decks.share_token`/`shared_at`/`share_revoked_at`, `DeckSharesController` POST/DELETE, `PublicDecksController` at `GET /d/:token` plus `GET /d/:token/export.{text,csv,json}` and `GET /d/:token/analysis.{markdown,json}`. The public page renders decklist + deterministic analysis + bracket + legality + suggestions only — AI runs, performance, collection fit, and matchup notes stay private.)
- [x] Extend account export to cover collection, sessions, and matchup notes once those slices land. (`Accounts::Exporter` schema bumped to v2; payload now carries collection cards + import history, game-night players/decks/seats/results, and matchup notes; export audit metadata records the new counts.)
- [x] PostgreSQL `pg_dump` backup script + scheduled timer + a documented restore drill. (`bin/backup_db` dumps all four production databases under `$BACKUP_ROOT` with custom-format pg_dump, sha256 manifest, and date-keyed retention; `bin/restore_db_drill` re-checks sha256 and pg_restores into a throwaway database; `config/systemd/ideal-magic-backup.{service,timer}` ship the canonical 03:30 UTC daily timer; `docs/runbooks/postgres-backups.md` covers install, manual run, restore-for-real, and failure modes.)
- [x] Operator runbook for the daily Scryfall corpus refresh job. (`docs/runbooks/scryfall-corpus-refresh.md` documents the 10:30 UTC `Scryfall::CardCorpusRefreshJob` schedule, manual `perform_now`/`perform_later` flow, monitoring via `card_corpus_refreshes`, retry/backoff behavior, and the deliberately-separate Commander legality-snapshot import.)

---

## Recent slices

Newest first. One line per shipped tranche.

- 2026-05-07 — Slice 11 closed: Codex auth polling now avoids unauthenticated `account/rateLimits/read` calls until `account/read` returns an account, per-user `CODEX_HOME` writes file-backed credential config, production Active Record encryption keys are env-backed, the sign-in page makes device-code the production-safe hosted path and labels browser OAuth as same-machine-only, and the live systemd unit/root path are verified for `/var/lib/ideal-magic/codex`.
- 2026-05-07 — Slice 11 opened: Codex App Server transport is now multi-tenant. `Codex::UserHome` owns per-user `CODEX_HOME=<root>/<user.id>/` (mode 0700, root from `CODEX_HOME_ROOT`); `AppServerClient.for(user)` builds a fresh client per request whose `StdioTransport` spawns codex with the user's `CODEX_HOME` and an explicit env allowlist (no Rails secrets forwarded); `AccountConnections.for(user)` and `EvaluationRunner.run!` resolve clients per-user so two concurrent runs for two different users cannot share a transport; logout, codex-disconnect, and account deletion all `UserHome.purge!`; `refresh_status` disconnects the local row when `auth.json` is missing on disk. Production systemd wiring (`CODEX_HOME_ROOT`, `ReadWritePaths=/var/lib/ideal-magic/codex`) is documented in `docs/deployment.md` and applied at deploy time.
- 2026-05-07 — Slice 10 opened: AI deck evaluation now runs prompt `deck-eval-v2` against schema `deck-evaluation-v2`. The LLM is fed the long-form Commander Brackets rules text, the canonical Game Changers list, the current Commander banlist, and the six-axis 0-10 power-band rubric via `Codex::BracketBriefing`, then makes the bracket call, sub-band call, and the six axis calls itself. `Decks::AiEvaluationPresenter` + the new `decks/_ai_analysis.html.erb` partial surface the AI evaluation as the canonical deck read once a v2 run succeeds, with the deterministic numbers collapsed into a "preliminary deterministic read" disclosure. The deck page also surfaces a one-click "Connect ChatGPT / Codex account" CTA when no Codex account is linked. Pod evaluation continues to use the v1 augmentation schema; `EvaluationRunner` picks the validator per target.
- 2026-05-07 — Slice 9 closed: daily `pg_dump` backups via `bin/backup_db` (custom-format dumps + sha256 manifest + date-keyed retention) wired through `config/systemd/ideal-magic-backup.{service,timer}` at 03:30 UTC, restore drill (`bin/restore_db_drill`) verifies manifest sha256 and pg_restores into a throwaway database, and operator runbooks for both PostgreSQL backups (`docs/runbooks/postgres-backups.md`) and the daily Scryfall corpus refresh (`docs/runbooks/scryfall-corpus-refresh.md`) ship in-tree, with `docs/deployment.md` updated to point at them.
- 2026-05-07 — Slice 9 public deck + analysis share links: decks gain opt-in revocable share tokens (`share_token` / `shared_at` / `share_revoked_at`) issued + revoked through `DeckSharesController`, the deck show page surfaces the public URL with explicit "playgroup notes stay private" copy, and `PublicDecksController` exposes the read-only deck page at `GET /d/:token` plus token-gated `export.{text,csv,json}` and `analysis.{markdown,json}` downloads — public surface intentionally omits AI runs, table performance, collection fit, matchup notes, and audit history.
- 2026-05-07 — Slice 9 deck + analysis exports and broader account export: deck show page surfaces plain-text/CSV/JSON decklist and Markdown/JSON deterministic-analysis downloads via `Decks::Exporter` + `Decks::AnalysisExporter` and dedicated controllers; account export bumps to schema v2 with collection cards + import history, game-night players/decks/seats/results, and matchup notes; export audit metadata records the new counts; `csv` added to the Gemfile (Ruby 4.0 no longer ships it as a default gem) and a `text/markdown` MIME type registered.
- 2026-05-07 — Slice 8 mobile nav + filters + honest offline UX: fixed five-up mobile bottom nav for authenticated users (Decks/Pods/Sessions/Journal/Collection) with active-section highlighting via `ApplicationController#mobile_nav_section`, deck index gains search-by-name/commander plus bracket and status filters, and a global `offline` Stimulus controller surfaces a "nothing has reached the server yet" banner and disables `[type=submit]` inside `form[data-offline-disable]` across deck import, AI evaluation, pod creation, session creation/seating/result, matchup-note CRUD, and collection forms.
- 2026-05-07 — Slice 8 PWA shell: dynamic `/manifest.json` + `/service-worker.js` routes wired to `rails/pwa#*`, manifest carries Ideal Magic branding, maskable + 192/512 icon variants, and Decks/Pods/Sessions shortcuts; the SW versions its caches by asset version + app revision, cache-firsts the app shell, network-firsts allowlisted deck/pod/session navigations with a tagged offline fallback, and the layout links the manifest, declares iOS/Android home-screen metadata, and mounts a `pwa-update` Stimulus banner that prompts a reload when a waiting worker is detected.
- 2026-05-07 — Slice 7 closed: deck and pod pages can queue quota-checked Codex AI evaluations; `CodexEvaluationJob` runs the App Server turn, validates the scorecard response, stores replayable prompt/model/input/output/latency/rate-limit metadata on `AnalysisRun`, and renders summaries, cited adjustments, friction drivers, Rule 0 talking points, recommendations, and queued/running/failed/stale states beside deterministic evidence.
- 2026-05-07 — Slice 7 prompt contracts: added the v1 Codex scorecard response schema + validator, single-deck and pod prompt builders that pass deterministic facts under citeable `fact.*` IDs, and recorded-fixture tests for prompt facts → response → schema validation without live calls.
- 2026-05-07 — Slice 7 opened: Codex account-auth now has a feature-flagged stdio JSON-RPC transport for the documented App Server `account/*` methods, keeps `NullTransport` as the default fail-closed path, normalizes account/rate-limit responses into existing account records, and has focused service/controller coverage.
- 2026-05-06 — Slice 6 meta trends: completed game-night results now drive post-game note prompts for wins/losses/draws/short games/dead draws/missing collection cards, deck table-performance summaries, revision-level result history from seat snapshots, commander meta tables with confidence/trend labels, and focused service/controller coverage.
- 2026-05-06 — Slice 6 opened: matchup notes now store deck-linked table memory with optional commander, opponent, saved pod, session pod number, normalized tags, account-scoped CRUD/search, journal navigation, and session seating context that surfaces recent notes matching the seated decks, commanders, or opponents.
- 2026-05-06 — Slice 5 closed: collection pages now rank shared missing-card demand pressure across decks, and deck tuning suggestions are labeled with matching owned options versus likely borrow/trade/buy gaps; focused service/controller/system tests cover the flow.
- 2026-05-06 — Slice 5 opened: collection storage, pasted/uploaded text and simple CSV import, manual quantity management, unresolved-row review, deck-page owned-vs-missing gaps, and focused service/controller/system tests are in place; demand pressure and recommendation ownership labels remain open.
- 2026-05-05 — Slice 4 closed: sessions now suggest bracket/power-balanced pod seating with manual pod/seat overrides, snapshot seated decks plus latest deterministic analysis, record winner/draw/turns/win-condition/notes, and render a session summary; focused model/controller tests plus a create → check-in → seat → record → summary system test cover the flow.
- 2026-05-05 — Slice 4 opened: game-night sessions now have `GameNight`-named models to avoid auth `Session` collision, user-owned players, check-in records, deck-of-the-night snapshots, pod-seat/result model foundations, `/sessions` index/new/show pages, dashboard/header links, and focused model/form/controller tests.
- 2026-05-05 — Slice 3 SEO + docs: full Twitter cards, per-page canonical links, site-wide `Organization` + `WebSite` JSON-LD via `ApplicationHelper#jsonld_tag`, `Article` + `BreadcrumbList` JSON-LD on bracket pages, `/sitemap.xml` route + view, sitemap-aware `robots.txt`, and a new `docs/public-site.md` covering routes, content workflow, and SEO baseline.
- 2026-05-05 — Slice 2 closed: pods now accept one guest deck via pasted decklist or public Archidekt / Moxfield URL. Guest decks attach to the pod (user_id=nil, guest_for_pod_id=pod.id), are analyzed inline, surface in the Rule 0 brief, and are destroyed when the pod is removed. Added `decks.guest_for_pod_id` reference column, `Pod#guest_decks` cascade, `PodForm` guest fields, and pod-controller + form-test coverage for paste / Archidekt-URL / multi-source / unparseable-decklist cases.
- 2026-05-05 — Slice 3 follow-up: refreshed the legality snapshot to the 2026-02-09 banlist (Biorhythm unbanned, Lutri removed since Commander format does not assign companions), added a Tymna + Thrasios Thoracle/Consultation cEDH fixture that locks in Bracket 5 in `BenchmarkScoringTest`, and added bracket-aware `Pods::AnalyzerTest` cases (mismatched 2→5 four-pod produces `bracket_mismatch` alert; balanced Bracket 2 three-pod produces a single-bracket headline).
- 2026-05-05 — Slice 3 opened: Commander Brackets (1–5) added as the primary deck-intent axis alongside the existing six axes; canonical Game Changers list, bracket evaluator service, deck/pod show pages surfacing the bracket badge + restrictions, and a public marketing surface (no-login landing + `/brackets` long-form explanation, About, Privacy, Terms). 0–10 axes are kept as sub-band evidence.
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

- Calibrate score bands and bracket placements against actual precon / casual / upgraded / high-power / cEDH decks once Slice 1 + Slice 3 ship and Stephen + a small group can play with it.
- Tune the salt/social-friction taxonomy from observed playgroup feedback.
- Run a closed beta of pod evaluation and session recording with Stephen's actual playgroup before declaring v1.
- Decide whether passkeys/WebAuthn lands before or after v1 based on how often password-only auth becomes friction.

If real-world feedback changes the engineering picture, fold the result into a slice above and check the affected boxes there.

## External truth to re-check before scaffolding integrations

- Scryfall asks for <10 req/s and bulk data for large workloads.
- Commander rules + banlist live at mtgcommander.net. Latest official update visible on 2026-05-04 was the 2024-09-23 quarterly update.
- Commander Brackets (beta) are a Wizards property. Latest official update referenced is 2026-02-09: Farewell + Biorhythm added to Game Changers, Biorhythm unbanned, Lutri remains companion-banned only. Re-check before shipping bracket-list changes.
- Codex App Server account-auth endpoints at https://developers.openai.com/codex/app-server are the supported surface for v1 AI.
- Archidekt has a publicly observable API for public decks but no formal docs — adapter may break.
- Moxfield has public deck pages and a public API (`api2.moxfield.com/v3/decks/all/<slug>`) but no formal docs — same caveat.

Re-check versions and endpoints when starting a new integration; trust the latest source over this file.
