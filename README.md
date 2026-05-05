# Ideal Magic

The serious Commander companion: import a deck, get an honest read on it under Wizards' official Commander Brackets system, build pods that actually feel fair, remember every game night, and turn your real playgroup into useful tuning advice.

Ideal Magic is a web app for Magic: The Gathering Commander players who want more than a power level guess. It places decks on the official 1–5 Commander Brackets, scores them from real evidence, compares pods before the cards hit the table, and remembers what happened the last time these commanders met.

Live at [ideal-magic.com](https://ideal-magic.com). The bracket guide, Game Changers list, and pregame template are public — no account needed to read them.

## What Ideal Magic Does

- **Place a deck on the Commander Brackets** (1 Exhibition · 2 Core · 3 Upgraded · 4 Optimized · 5 cEDH) with the Game Changers, mass land denial, extra turns, and two-card combos that drove the call.
- **Import a deck** by paste, text export, or public Archidekt / Moxfield URL.
- **Sub-band it honestly** with six 0–10 axes — Power, Speed, Interaction, Consistency, Salt, and Social Friction — that explain *where inside* a bracket the deck sits.
- **See your collection** mapped against every deck so you know what you already own, what you're missing, and which cards your library is hungry for.
- **Compare pods** of 2 to 4 decks before a game starts, get the bracket spread, and produce a copy-pasteable Rule 0 brief.
- **Run game nights** with player check-in and deck registration; pod seating and result recording are the next layer.
- **Keep a matchup journal** tied to decks, commanders, opponents, pods, and sessions.
- **Watch your meta** evolve over time across decks, commanders, players, win conditions, and friction.
- **Get tuning advice** that uses the cards you actually own and the games you actually played.
- **Install as a PWA** on phone, tablet, or desktop and use it at the table.

## Public Surface

You can read the bracket guide and reference pages without an account:

- [`/brackets`](https://ideal-magic.com/brackets) — the long-form Commander Brackets explanation.
- [`/brackets/game-changers`](https://ideal-magic.com/brackets/game-changers) — the canonical Game Changers list, grouped by play pattern.
- [`/brackets/pregame-template`](https://ideal-magic.com/brackets/pregame-template) — the Rule 0 template with worked examples.

Importing decks, building pods, and running analysis still require an account.

## Why It's Different

- **Evidence over vibes.** Open any score and see exactly which cards and patterns produced it. No mystery numbers.
- **Built for the table.** Mobile-first. Fast. Readable in a noisy game store at 9 PM.
- **Knows your collection.** Recommendations distinguish what you own from what you'd have to buy.
- **Remembers your group.** Real game-night history feeds future advice instead of vanishing into a notebook.
- **Salt as conversation, not judgment.** Salt and social-friction scores help Rule 0 talks happen earlier — they don't shame players for liking what they like.
- **Source-backed facts.** Card data and Commander legality come from deterministic sources, never model guesses.
- **Self-hostable and inspectable.** Owned by the person who runs it.

## How It Reads a Deck

The headline output is a **Commander Bracket** placement (1–5) plus a sub-band (`low`, `mid`, `high`) inside that bracket. The bracket call is deterministic, runs against a source-controlled Game Changers catalog and two-card-combo list, and surfaces the cards that drove the placement.

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

Ideal Magic is in active build and runs live at [ideal-magic.com](https://ideal-magic.com) so the product can be iterated against the real domain. The Rails foundation, card corpus pipeline, Commander legality engine, account system, deck import, deterministic scoring, pods, game-night session check-in, and the self-hosted deployment shape are in place. AI evaluation, pod seating/results, the matchup journal, meta analytics, and the PWA shell are still being built.

Build sequencing and current repo truth live in [BUILD.md](BUILD.md). Operational runbook for the live deployment lives in [docs/deployment.md](docs/deployment.md).

## Documentation

- [docs/product-scope.md](docs/product-scope.md) — what Ideal Magic does and where it draws the line.
- [docs/analysis-rubric.md](docs/analysis-rubric.md) — how scores are computed, banded, and explained.
- [docs/provider-integrations.md](docs/provider-integrations.md) — which deck and collection sources are supported and why.
- [docs/security.md](docs/security.md) — auth, secret handling, privacy, and fan-content boundaries.
- [docs/deployment.md](docs/deployment.md) — the intended self-hosted deployment shape.
- [BUILD.md](BUILD.md) — active build execution manual.
- [AGENTS.md](AGENTS.md) — repo-local operating rules for contributors.

## For Developers

Ideal Magic is a Ruby on Rails monolith. To run it locally:

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

`bin/redeploy` pulls, bundles, runs `db:prepare`, precompiles assets, restarts the systemd unit, and then health-checks `https://ideal-magic.com/up`. See [docs/deployment.md](docs/deployment.md) for the full deployment shape.

Use `mise` (or another Ruby version manager that honors `.ruby-version` / `.mise.toml`) to select the pinned Ruby. Stack details, dependencies, and the full build sequence live in [BUILD.md](BUILD.md).

## Fan Content Notice

Ideal Magic is unofficial fan content. It is not approved, endorsed, or sponsored by Wizards of the Coast.

Portions of Magic: The Gathering materials are property of Wizards of the Coast LLC. Use of card names, card text, images, and related material follows Wizards' Fan Content Policy and source-specific data terms.

## License

Ideal Magic is licensed under the GNU General Public License, version 3. See [LICENSE](LICENSE) for the full text.

```
GNU GENERAL PUBLIC LICENSE
Version 3
```
