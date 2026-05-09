# Pod Tracker

The serious Commander companion: import a deck, get an honest read on it under Wizards' official Commander Brackets system, build pods that actually feel fair, remember every game night, and turn your real playgroup into useful tuning advice.

Pod Tracker is a web app for Magic: The Gathering Commander players who want more than a power level guess. It places decks on the official 1–5 Commander Brackets, scores them from real evidence, compares pods before the cards hit the table, and remembers what happened the last time these commanders met.

Live at [pod-tracker.app](https://pod-tracker.app). The bracket guide, Game Changers list, and pregame template are public. Deck imports, collection tracking, pods, game nights, and evaluations require an account.

## Current Capabilities

- **Place a deck on the Commander Brackets** (1 Exhibition · 2 Core · 3 Upgraded · 4 Optimized · 5 cEDH) with the Game Changers, mass land denial, extra turns, and two-card combos that drove the call.
- **Import a deck** by paste, text export, or public Archidekt / Moxfield URL.
- **Sub-band it honestly** with six 0–10 axes: Power, Speed, Interaction, Consistency, Salt, and Social Friction.
- **See your collection** mapped against every deck so you know what you already own, what you're missing, and which cards your library is hungry for.
- **Compare pods** of 2 to 4 decks before a game starts, get the bracket spread, and produce a copy-pasteable Rule 0 brief.
- **Run game nights** with player check-in, deck registration, suggested pod seating, manual seat overrides, and result recording.
- **Keep a matchup journal** tied to decks, commanders, opponents, pods, and sessions, with searchable tags and prior notes surfaced during session seating.
- **Watch your meta** evolve over time across decks, commanders, recorded results, deck revisions, win conditions, and friction.
- **Get tuning advice** that uses the cards you actually own and the games you actually played.
- **Export your data** as decklists, JSON/CSV payloads, Markdown analyses, and account exports.
- **Share deliberately** with opt-in, revocable deck and pod links that omit playgroup notes, collection fit, opponent identity, and audit history.
- **Install as a PWA** on phone, tablet, or desktop and use it at the table.

## Public Surface

You can read the bracket guide and reference pages without an account:

- [`/brackets`](https://pod-tracker.app/brackets) — the long-form Commander Brackets explanation.
- [`/brackets/game-changers`](https://pod-tracker.app/brackets/game-changers) — the canonical Game Changers list, grouped by play pattern.
- [`/brackets/pregame-template`](https://pod-tracker.app/brackets/pregame-template) — the Rule 0 template with worked examples.

Opt-in deck and pod share links are also anonymous-readable when a signed-in user enables them. They are intentionally unlisted and revocable.

## Why It's Different

- **Evidence over vibes.** Open any score and see exactly which cards and patterns produced it. No mystery numbers.
- **Built for the table.** Mobile-first. Fast. Readable in a noisy game store at 9 PM.
- **Knows your collection.** Recommendations distinguish what you own from what you'd have to buy.
- **Remembers your group.** Real game-night history feeds future advice instead of vanishing into a notebook.
- **Salt as conversation, not judgment.** Salt and social-friction scores help Rule 0 talks happen earlier — they don't shame players for liking what they like.
- **Source-backed facts.** Card data and Commander legality come from deterministic sources, never model guesses.
- **Self-hostable and inspectable.** Owned by the person who runs it.

## How It Reads a Deck

The headline output is a **Commander Bracket** placement (1–5) plus a sub-band (`low`, `mid`, `high`) inside that bracket. Once a deck has been imported, Pod Tracker shows a deterministic preliminary read against a source-controlled Game Changers catalog and two-card-combo list.

The user can then run an **AI evaluation** against their own ChatGPT/Codex account. The model receives the Commander Brackets rules text, Game Changers list, Commander banlist, deck name, decklist, oracle text, and Pod Tracker's role/salt/friction tags. A successful AI evaluation becomes the canonical deck read on the show page, with the deterministic numbers tucked behind a "preliminary read" disclosure.

Card legality stays deterministic regardless. The AI cannot override the banlist.

The six 0–10 axes sub-band the bracket — they explain whether a Bracket 3 deck sits at the low end (close to Bracket 2) or pressing against Bracket 4:

| Score | What it measures |
| --- | --- |
| **Power** | Ability to win against prepared Commander tables. |
| **Speed** | How quickly the deck threatens a win or dominant board. |
| **Interaction** | How well it answers threats and protects its plan. |
| **Consistency** | How reliably it executes its game plan. |
| **Salt** | Likelihood of producing frustration at a typical table. |
| **Social Friction** | How much Rule 0 conversation a deck or pod likely needs. |

Pod analysis aggregates bracket spread, GC count, and combo disclosures into a copy-pasteable Rule 0 brief.

Full rubric: [docs/analysis-rubric.md](docs/analysis-rubric.md).

## Status

Pod Tracker runs live at [pod-tracker.app](https://pod-tracker.app), and the planned v1 build is complete.

Shipped product areas:

- Rails account system with email verification, password reset, account deletion, account export, and audit events.
- Scryfall-backed card corpus, Commander legality snapshots, Commander Brackets data, Game Changers, and two-card combo catalogs.
- Deck import, deck revisions, deterministic scoring, Codex-backed deck evaluations, exports, and revocable public deck shares.
- Collection import, owned/missing deck comparisons, demand pressure, and collection-aware recommendations.
- Pod comparison, Codex-backed pod evaluations, table roles, Rule 0 briefs, and revocable public pod shares.
- Game-night check-in, deck registration, suggested pod seating, result recording, matchup notes, post-game prompts, and meta summaries.
- Installable PWA shell with offline-readable recent pages, a reload prompt, an offline write-state banner, mobile bottom navigation, and responsive deck filters.
- Self-hosted deployment on the production VM with Caddy, Puma under systemd, PostgreSQL, Solid Queue in Puma, daily database backups, and `bin/redeploy`.

Single-deck AI evaluation is authoritative for bracket placement and the six power-band axes once a Codex run succeeds. Pod AI evaluation is authoritative for pod bracket spread, table-fit axes, per-deck table roles, and the Rule 0 brief. Deterministic reads stay as preliminary fallbacks.

The deck and pod prompts run on `deck-eval-v3` / `pod-eval-v3` against the unchanged v2 response schemas. Prompt changes can move independently from schema changes; see `AGENTS.md` for the versioning contract.

Operational runbook for the live deployment lives in [docs/deployment.md](docs/deployment.md). Repo-local operator and product rules live in [AGENTS.md](AGENTS.md).

## Documentation

- [docs/product-scope.md](docs/product-scope.md) — what Pod Tracker does and where it draws the line.
- [docs/analysis-rubric.md](docs/analysis-rubric.md) — how scores are computed, banded, and explained.
- [docs/provider-integrations.md](docs/provider-integrations.md) — which deck and collection sources are supported and why.
- [docs/security.md](docs/security.md) — auth, secret handling, privacy, and fan-content boundaries.
- [docs/deployment.md](docs/deployment.md) — the intended self-hosted deployment shape.
- [docs/runbooks/postgres-backups.md](docs/runbooks/postgres-backups.md) — daily `pg_dump` backups, retention, and the restore drill.
- [docs/runbooks/scryfall-corpus-refresh.md](docs/runbooks/scryfall-corpus-refresh.md) — the daily Scryfall card-corpus refresh job.
- [AGENTS.md](AGENTS.md) — repo-local operating rules for contributors.

## For Developers

Pod Tracker is a Ruby on Rails monolith. To run it locally:

```sh
bin/setup
bin/dev
```

Quality gates:

```sh
bin/test
bin/lint
bin/security
bin/verify
```

To redeploy the live site after pulling or pushing changes (run on the production VM as the `sawyer` user):

```sh
bin/redeploy
```

`bin/redeploy` pulls, bundles, runs `db:prepare`, precompiles assets, restarts the systemd unit, and then health-checks `https://pod-tracker.app/up`. See [docs/deployment.md](docs/deployment.md) for the full deployment shape.

Use `mise` (or another Ruby version manager that honors `.ruby-version` / `.mise.toml`) to select the pinned Ruby. The stack is Ruby 4.0.3, Rails 8.1.3, PostgreSQL 17, Hotwire, Tailwind CSS v4, ViewComponent, Propshaft, and Solid Queue / Cache / Cable in Puma.

Quality gates run through `bin/verify`: RuboCop, ERB lint, bundler-audit, importmap audit, Brakeman, Rails tests, system tests, and seed replant. On the production VM, see [AGENTS.md](AGENTS.md) for the test database and Bundler setup notes before running tests.

## Fan Content Notice

Pod Tracker is unofficial fan content. It is not approved, endorsed, or sponsored by Wizards of the Coast.

Portions of Magic: The Gathering materials are property of Wizards of the Coast LLC. Use of card names, card text, images, and related material follows Wizards' Fan Content Policy and source-specific data terms.

## License

Pod Tracker is licensed under the GNU General Public License, version 3. See [LICENSE](LICENSE) for the full text.

```
GNU GENERAL PUBLIC LICENSE
Version 3
```
