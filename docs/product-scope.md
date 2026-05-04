# Product Scope

Ideal Magic is Stephen's primary Magic: The Gathering product. It should absorb the best durable ideas from the retired Scrybase direction while staying on the Rails architecture already chosen for Ideal Magic.

The product should become a Commander operating surface, not only a deck checker. The center is still transparent deck and pod evaluation, but the long-term advantage comes from connecting decks, owned cards, game-night history, matchup notes, and real playgroup meta evidence.

## Core Lanes

### Deck Lab

Deck Lab owns deck import, editing, version history, deterministic analysis, Codex-backed scorecards, combo detection, cuts, upgrades, exports, and public/private sharing.

Expected durable concepts:

- Pasted decklists, text exports, public Archidekt URLs, and public Moxfield URLs.
- Manual edit fallback when imports are incomplete.
- Deck revisions with diffs and analysis history.
- Mana curve, color-pip pressure, land count, source count, role balance, combo candidates, cut candidates, and upgrade recommendations.
- Opening-hand and early-turn consistency simulation where feasible.
- Markdown, text, JSON, and decklist exports.

### Collection Base

Collection Base owns the user's physical or digital card inventory without becoming a finance or marketplace product.

Expected durable concepts:

- Pasted or uploaded collection exports.
- Owned, foil, condition, source, and import history fields.
- Owned-versus-missing comparison for each deck.
- Demand pressure across the user's deck library.
- Collection-aware upgrade suggestions, including cards already owned and cards missing from multiple lists.
- Optional price snapshots only as tuning context, not a trading marketplace.

### Pod Intel

Pod Intel owns table setup before a game starts and game-night history after it ends.

Expected durable concepts:

- Sessions with date, location, notes, status, and share controls.
- Player check-in.
- Deck registration per player.
- Pod preview and seating for 2 to 4 deck evaluation, with later support for larger event-style seating when it earns scope.
- Result recording with winner, draw state, turns, win condition, and notes.
- Public session summaries by share link when explicitly enabled.

### Matchup Journal

Matchup Journal owns human context that raw decklists cannot capture.

Expected durable concepts:

- Notes tied to decks, commanders, opposing commanders, players, pods, and sessions.
- Tags for recurring problems, archetypes, social friction, and tactical lessons.
- Pre-game briefs that surface prior notes when the same deck, commander, or opponent returns.
- Post-game review prompts that ask what overperformed, what stalled, what was missing, and what should change.

### Meta And Tuning

Meta and tuning turns recorded play into better decisions.

Expected durable concepts:

- Deck, commander, player, pod, and win-condition trends.
- Revision performance, including whether a deck improved after changes.
- Pod balance history and mismatch patterns.
- Salt and social-friction trends separated from raw power.
- Recommendations that combine deterministic deck facts, collection ownership, and real playgroup outcomes.

## Product Principles

- Source-backed facts first. Scryfall, Commander rules snapshots, imported decks, collection data, and recorded results are the truth layer.
- AI interprets evidence; it does not invent card facts, legality, results, or private history.
- Collection features help users build and tune from cards they own. They do not become a marketplace.
- Playgroup memory should be useful without being creepy. Private notes stay private unless explicitly shared.
- Public links should be opt-in, revocable, and scoped to the specific deck, analysis, pod, or session.
- The app should be fast enough to use at a Commander table on a phone.

## Replacement Direction

Ideal Magic replaces Scrybase as the single primary Magic project. Do not port Scrybase's Python, FastAPI, Astro, Elysia, OpenTUI, or migration architecture. Preserve the product lessons and rebuild them in Rails using Ideal Magic's current stack and build phases.
