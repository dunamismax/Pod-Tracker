# BUILD.md

Active build manual for Ideal Magic. Reading this plus `AGENTS.md` and `README.md` is enough context to ship.

Last updated: 2026-05-06 (Slice 5 — collection import and deck gaps)

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
- **Collection:** signed-in users can import owned cards from pasted text, uploaded text, or simple CSV, manually add/edit/remove card quantities, review unresolved rows, and see owned-vs-missing deck gaps on each deck page.
- **Pods (2–4 decks):** build a pod from your own decks, optionally including one guest deck via pasted decklist or public Archidekt / Moxfield URL. Pods get per-axis spread/average/outliers, archenemy/pubstomp/durdle warnings, a Rule 0 brief (power band, tempo, combo/stax notes, salt/friction notes), and per-deck swap suggestions. Mobile-readable and printable show page. Opt-in revocable public share link. Guest decks live only with the pod and are removed when the pod is removed.
- **Game-night sessions:** signed-in users can create a session at `/sessions`, save date/location/notes, create or reuse user-owned players, and check each player in with one owned deck of the night. Sessions suggest pod seating from the checked-in roster, allow manual pod/seat overrides, snapshot each seated deck's name, commanders, deck timestamp, card count, and deterministic analysis, record pod results, and render a session summary.
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
- [ ] Demand pressure: which missing cards matter across multiple decks.
- [ ] Recommendations distinguish "you already own this" from "you'd have to buy it." No price/marketplace flow.
- [x] Tests: import parser, ownership service, system test for collection → deck gaps.

### Slice 6 — Matchup journal and meta trends

- [ ] Matchup note model: belongs to user, links to deck, commander, opponent (player), pod, session. Tags + free text.
- [ ] Note CRUD with search by tag, deck, commander, player, pod, session.
- [ ] Pre-game context surface: when seating a pod, show prior notes for those decks/commanders/opponents.
- [ ] Post-game prompt for wins/losses/draws/short games/dead draws/missing cards.
- [ ] Deck performance: games, wins, draws, win rate with sample-size confidence, average turns, last played.
- [ ] Commander meta: appearances, wins, win rate, recent trend. Sample size visible; never pretend thin data is certain.
- [ ] Revision performance: connect deck revisions to results so "what changed since this deck last won" is answerable.
- [ ] Tests: matchup search, meta service against fixture sessions.

### Slice 7 — Codex AI evaluation as augmentation

The v1 differentiator. Build it on top of deterministic analysis, not as a replacement.

- [ ] Implement a real Codex App Server JSON-RPC transport against the documented account-auth surface. Replace `NullTransport` with the live client behind a feature flag.
- [ ] JSON schema for AI scorecards: power/speed/interaction/consistency/salt/social-friction adjustments, friction drivers, Rule 0 talking points. Cite deterministic facts; mark uncertainty.
- [ ] Single-deck prompt v1: pass the deterministic feature vector, decklist, commander, combo candidates, salt/friction evidence, and rubric. Ask for adjustments + explanations, not raw scores.
- [ ] Pod prompt v1: same shape, pod-aware.
- [ ] Background job that runs evaluation against a quota-checked Codex account; surfaces queued / running / failed / stale states on the deck and pod pages.
- [ ] Replayable runs: store prompt version, model, inputs, outputs, latency, and rate-limit snapshot per `AnalysisRun`.
- [ ] Recorded-fixture tests for the prompt → response → schema validation path. No live calls in CI.
- [ ] AI explanations render alongside deterministic evidence; the deterministic numbers stay visible.

### Slice 8 — PWA and table-side polish

- [ ] Web app manifest, service worker, app-shell cache.
- [ ] Recent decks and analyses cached for read-only offline access.
- [ ] iOS home-screen + Android maskable icon coverage.
- [ ] Cache versioning and an update prompt that doesn't trap users on stale assets.
- [ ] Mobile bottom nav, desktop sidebar nav, responsive deck-list controls (search, tag filter, role filter).
- [ ] Honest offline states: never pretend AI runs, imports, or new results have reached the server while offline.

### Slice 9 — Exports, share links, and operational polish

- [ ] Deck export to plain text, CSV, and JSON from the deck show page.
- [ ] Analysis export to Markdown and JSON.
- [ ] Public deck and analysis share links with opt-in revocation; safe defaults (no playgroup notes leak).
- [ ] Extend account export to cover collection, sessions, and matchup notes once those slices land.
- [ ] PostgreSQL `pg_dump` backup script + scheduled timer + a documented restore drill.
- [ ] Operator runbook for the daily Scryfall corpus refresh job.

---

## Recent slices

Newest first. One line per shipped tranche.

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
