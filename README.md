# Ideal Magic

Ideal Magic is a planned Ruby on Rails web app for AI-assisted Magic: The Gathering Commander deck and pod evaluation.

The goal is to build a better, more transparent version of the deck-checking experience: import decks from public Archidekt or Moxfield links, analyze them with deterministic Commander heuristics plus OpenAI-backed evaluation, and return clear scores for power, speed, interaction, consistency, and pod fit.

Ideal Magic will be hosted at `ideal-magic.com` on Stephen's Ubuntu VM behind Caddy.

## Current Status

This repository is at the planning stage. The Rails application has not been scaffolded yet.

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

## Important OpenAI Constraint

The desired "sign in with ChatGPT and use the user's ChatGPT subscription for backend work" flow is not currently a safe product assumption.

OpenAI's API uses API keys, and ChatGPT billing is separate from API billing. Ideal Magic should therefore support these v1 modes:

- Stephen/app-owned OpenAI API billing.
- Optional encrypted bring-your-own OpenAI API key mode.
- Future official OpenAI OAuth or ChatGPT app integration only if OpenAI publishes a supported flow for it.

Ideal Magic must not ask users for ChatGPT passwords, scrape ChatGPT, expose API keys to browsers, or imply that a ChatGPT Plus/Pro subscription pays for API calls.

## Core Scores

Ideal Magic will store scores internally on a 0-100 scale and display them as friendly numeric scores with bands and explanations.

- Power: overall ability to win against prepared Commander tables.
- Speed: how quickly the deck can present a win attempt or dominant board.
- Interaction: how well it can answer threats and protect its own plan.
- Consistency: how reliably it executes its intended game plan.
- Pod Fit: how well multiple decks match each other for a Commander game.

Each score should include confidence, evidence, and suggested improvements.

## Planned Stack

- Ruby latest stable at scaffold time.
- Rails latest stable at scaffold time.
- PostgreSQL for durable data.
- Rails authentication as the baseline account system.
- Hotwire, Turbo, Stimulus, Tailwind CSS v4, and Rails-native components for the UI.
- Solid Queue for background deck analysis.
- Solid Cache and Solid Cable where they earn their keep.
- Scryfall bulk data for card facts.
- OpenAI Responses API for structured AI evaluation.
- Docker Compose for local and self-hosted runtime.
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

## Deployment Target

The intended production shape is a single self-hosted Ubuntu VM:

- Caddy terminates HTTPS for `ideal-magic.com`.
- Docker Compose runs the Rails web process, worker process, and PostgreSQL.
- systemd keeps the stack running after reboot.
- Backups run on a timer and have a documented restore path.

Kamal can be evaluated later, but the default path should stay inspectable through Docker Compose, Caddy, and systemd.

## Development

The app has not been scaffolded yet. The first implementation phase should create the Rails foundation and then update this section with real commands.

Expected future commands:

```sh
bin/setup
bin/dev
bin/rails test
bin/verify
```

## Project Boundary

Ideal Magic v1 is Commander-first. Other formats, native apps, Discord bots, collection finance, marketplace features, and full gameplay simulation are future work.

The v1 bar is simple: import decks reliably, analyze them honestly, explain the score, compare pods, and run beautifully on Stephen's own server.
