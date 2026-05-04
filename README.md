# Ideal Magic

Ideal Magic is a Ruby on Rails web app for AI-assisted Magic: The Gathering Commander deck and pod evaluation.

The goal is to build a better, more transparent version of the deck-checking experience: import decks from public Archidekt or Moxfield links, analyze them with deterministic Commander heuristics plus Codex-backed OpenAI evaluation, and return clear scores for power, speed, interaction, consistency, and pod fit.

Ideal Magic will be hosted at `ideal-magic.com` on Stephen's Ubuntu VM behind Caddy.

## Current Status

This repository has a verified Rails foundation and the first Phase 2 card corpus ingestion tranche. The app currently boots with Ruby 4.0.3, Rails 8.1.3, PostgreSQL, Hotwire, Tailwind CSS v4, ViewComponent, Solid Queue/Cache/Cable, Rails authentication, baseline quality gates, schema/model coverage for decks, card corpus records, analysis runs, scorecards, pod evaluations, salt/social-friction evidence, provider links, legality snapshots, and audit events, plus fixture-tested Scryfall bulk-data ingestion for card sets, oracle cards, card printings, and refresh snapshot metadata.

No deck import, card data refresh jobs, Commander legality engine, scoring engine, Codex evaluation pipeline, pod comparison workflow, PWA offline behavior, Docker Compose runtime, or production deployment configuration has shipped yet.

Current stable docs:

- [BUILD.md](/Users/sawyer/github/ideal-magic/BUILD.md) - active build execution manual.
- [AGENTS.md](/Users/sawyer/github/ideal-magic/AGENTS.md) - repo-local operating rules.
- [docs/analysis-rubric.md](/Users/sawyer/github/ideal-magic/docs/analysis-rubric.md) - initial score rubric.
- [docs/provider-integrations.md](/Users/sawyer/github/ideal-magic/docs/provider-integrations.md) - allowed provider integration policy.
- [docs/security.md](/Users/sawyer/github/ideal-magic/docs/security.md) - auth, secret, privacy, and fan-content boundaries.
- [docs/deployment.md](/Users/sawyer/github/ideal-magic/docs/deployment.md) - intended self-hosted deployment shape.

Build execution lives in [BUILD.md](/Users/sawyer/github/ideal-magic/BUILD.md). Future agents should treat that file as the active implementation manual until the app is built and these stable docs describe shipped behavior.

## Product Promise

Ideal Magic should help Commander players answer practical questions before a game starts:

- Is this deck likely to fit my table?
- How fast does it threaten a win or dominant board?
- Does it have enough interaction?
- Is the mana, draw, ramp, and redundancy good enough?
- Why did it receive this score?
- Which changes would move it closer to the desired power band?
- Are these four decks likely to create a fair and fun pod?

The scores must be evidence-backed. A user should be able to open an analysis and see which facts drove the result instead of receiving a mysterious number.

## AI Usage Auth Model

Ideal Magic's v1 AI path is ChatGPT/Codex account auth through OpenAI's documented Codex App Server flow.

Users connect their ChatGPT/Codex account with Codex-managed browser OAuth or device-code login. Ideal Magic then runs AI evaluation through Codex account auth and ChatGPT/Codex rate limits instead of app-owned per-token API billing.

This is not a generic OpenAI API OAuth flow. Ideal Magic must not call the OpenAI API with browser-visible keys, ask for ChatGPT passwords, scrape ChatGPT, hand-roll token refreshes, or claim that ChatGPT billing pays for arbitrary Responses API calls. The supported integration boundary is Codex App Server account auth.

The app should still track model choice, account plan metadata when available, rate-limit state, latency, failures, rubric versions, and all deterministic evidence used by an AI run.

## Core Scores

Ideal Magic will store scores internally on a 0-100 scale and display them as friendly numeric scores with bands and explanations.

- Power: overall ability to win against prepared Commander tables.
- Speed: how quickly the deck can present a win attempt or dominant board.
- Interaction: how well it can answer threats and protect its own plan.
- Consistency: how reliably it executes its intended game plan.
- Pod Fit: how well multiple decks match each other for a Commander game.

Each score should include confidence, evidence, and suggested improvements.

## Stack

- Ruby 4.0.3, pinned in `.ruby-version`, `.mise.toml`, and the Docker base image.
- Rails 8.1.3, pinned in `Gemfile.lock`.
- PostgreSQL for durable data.
- Rails authentication as the baseline account system.
- Hotwire, Turbo, Stimulus, Tailwind CSS v4, and ViewComponent for the UI.
- Solid Queue for background deck analysis.
- Solid Cache and Solid Cable are installed with the Rails foundation.
- Scryfall bulk data for card facts.
- OpenAI Codex App Server for structured AI evaluation through ChatGPT/Codex account auth.
- Docker image support is scaffolded; Docker Compose is not implemented yet.
- Caddy for TLS and reverse proxy at `ideal-magic.com`.
- systemd for service lifecycle and backup timers on the Ubuntu host.

## Planned Features

- Import by pasted decklist.
- Import by text export.
- Import from public Archidekt deck URLs.
- Import from public Moxfield deck URLs.
- Store deck versions and compare changes over time.
- Evaluate Commander legality, color identity, curve, mana, ramp, draw, tutors, interaction, win conditions, and combos.
- Generate AI-backed deck reports from deterministic facts.
- Compare 2 to 4 decks in a pod.
- Produce a Rule 0 conversation brief.
- Share public analysis links with privacy controls.
- Export analysis to Markdown, text, and JSON.
- Install as a polished PWA on mobile and desktop.
- Cache recent deck reports for read-only offline use.

## UX Direction

Ideal Magic should feel like a serious table-side tool, not a marketing page.

The first screen after login should be the working dashboard: import a deck, view recent analyses, open pods, and see queued work. Mobile layouts should be primary, with desktop taking advantage of space for comparison and evidence panels.

The interface should favor dense, readable information; fast actions; clear empty states; and score explanations that can be scanned at a table.

## Data And Legality

Card facts should come from Scryfall bulk data and deterministic rules, not model memory. Commander legality and color identity must be computed from source data.

Archidekt and Moxfield integrations should start with public deck URLs and exports. Authenticated account sync is a future feature only if the provider offers a documented and acceptable auth/API path.

## Fan Content Notice

Ideal Magic is unofficial fan content. It is not approved, endorsed, or sponsored by Wizards of the Coast.

Portions of Magic: The Gathering materials are property of Wizards of the Coast LLC. Any use of card names, card text, images, or related material must follow Wizards' Fan Content Policy and source-specific data terms.

The public app must include the fan-content notice on public legal/footer surfaces before launch.

## Repo Status

The GitHub repository is public as of 2026-05-03. No license file is present yet, so licensing is pending and reuse terms are not granted until Stephen chooses and commits a license.

## Deployment Target

The intended production shape is a single self-hosted Ubuntu VM:

- Caddy terminates HTTPS for `ideal-magic.com`.
- Docker Compose runs the Rails web process, worker process, and PostgreSQL.
- systemd keeps the stack running after reboot.
- Backups run on a timer and have a documented restore path.

Kamal can be evaluated later, but the default path should stay inspectable through Docker Compose, Caddy, and systemd.

## Development

Use `mise` or another Ruby version manager that can select Ruby 4.0.3. This repo includes `.ruby-version` and `.mise.toml`; with `mise`, run `mise trust` once for this checkout. If your shell does not auto-activate `mise`, prefix commands with `mise exec --`.

Current commands:

```sh
bin/setup
bin/dev
bin/test
bin/lint
bin/security
bin/build
bin/verify
```

Useful Rails commands:

```sh
bin/rails db:prepare
bin/rails test
bin/rails assets:precompile
```

## Project Boundary

Ideal Magic v1 is Commander-first. Other formats, native apps, Discord bots, collection finance, marketplace features, and full gameplay simulation are future work.

The v1 bar is simple: import decks reliably, analyze them honestly, explain the score, compare pods, and run beautifully on Stephen's own server.
