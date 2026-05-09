# Analysis Rubric

Pod Tracker scores Commander decks and pods from deterministic evidence first. AI evaluation may refine explanations and judgment later, but every score must remain traceable to stored facts, rubric versions, and source data.

The primary axis is Wizards' official Commander Brackets system (1–5). Six 0–10 sub-axes — power, speed, interaction, consistency, salt, and social friction — sub-band a deck *inside* its bracket and explain Rule 0 friction.

## Commander Brackets (primary axis)

The Commander Brackets system is the headline output of the analyzer. It sets the deck's expected experience, expected minimum turns, and the restrictions the pod can rely on.

| Bracket | Name | Mindset | Min turns | Game Changers | Mass land denial | Extra turns | Two-card combos |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Exhibition | Theme-first showcase | 9+ | None (rare Rule 0 exception) | No | No | No |
| 2 | Core | Casual, functional | 8+ | None | No | No chaining | No |
| 3 | Upgraded | Tuned casual | 6+ | Up to 3 | No | No chaining | Not before turn 6 |
| 4 | Optimized | High-power, non-cEDH | 4+ | Any | Allowed | Allowed | Allowed |
| 5 | cEDH | Competitive metagame | any | Any | Allowed | Allowed | Allowed |

The bracket evaluator (`Decks::BracketEvaluator`) runs deterministically against the deck's feature vector plus the Game Changers and two-card-combo catalogs (`db/seeds/commander/brackets/*.json`). Decks that look like cEDH builds (deep tutors + fast mana + GC stack + combo pressure) land in Bracket 5; decks that violate any Bracket 3 restriction (more than 3 GCs, MLD, chained extra turns, immediate-win combos) land in Bracket 4; everything else flows down through Brackets 3, 2, and 1 by the published gates.

The bracket call is augmented by a sub-band (`low`, `mid`, `high`) inside each bracket so a "low-power Bracket 3" deck and a "high-power Bracket 3" deck do not look identical in a pod brief. Sub-band reads the deterministic 0–10 power score, fast-mana count, tutor count, combo count, and GC count.

## Sub-band axes (0–10)

Sub-band axes are stored as integer 0–10 values and rendered with plain-language hints. They never override the bracket call — they describe how a deck sits inside it.

- 0: nonfunctional / illegal for the requested context.
- 1–3: very low pressure or heavily constrained.
- 4–6: typical of the bracket.
- 7–8: high-end of the bracket; close to the next gate.
- 9–10: pressing against the next bracket's restrictions.

Band labels are descriptive, not moral judgments. The UI should explain what moved a deck into a band and what would move it out.

## Shared Evidence Rules

Every scorecard must include:

- Rubric version.
- Analysis source versions for card corpus, Commander legality, and provider import.
- Confidence level.
- Deterministic feature vector.
- Positive evidence.
- Risk or weakness evidence.
- Suggested improvements tied to score movement.

The model must cite only facts supplied by the app. If a decklist is incomplete, malformed, missing card facts, or potentially stale, the score confidence should drop instead of inventing certainty.

When collection, session, and matchup data exist, scorecards may cite those facts separately from raw deck construction. The UI must make that distinction clear: a deck's inherent analysis, a user's owned-card opportunities, and a playgroup's actual history are different evidence classes.

## Power

Power measures the deck's ability to win against prepared Commander tables.

Primary inputs:

- Win condition density and clarity.
- Compact combo access and redundancy.
- Tutor density and tutor quality.
- Fast mana and high-impact acceleration.
- Card quality and mana efficiency.
- Commander dependency and commander resilience.
- Protection for the deck's own plan.
- Ability to recover from disruption.
- Known high-power staples and archetype markers.

Power should not be a simple average of speed, interaction, and consistency. A slow but oppressive control deck or a fragile glass-cannon combo deck can score differently from the component average.

## Speed

Speed estimates how quickly the deck can present a credible win attempt or dominant board state.

Primary inputs:

- Fast mana count and quality.
- Ramp count, mana value, and timing.
- Mana curve and early-turn plays.
- Tutor access to win conditions or engines.
- Card selection and opening-hand smoothing.
- Combo compactness.
- Commander mana value and setup cost.
- Opening-hand and early-turn probability checks where feasible.

Speed evidence should name expected turn ranges conservatively and include confidence. If the deck threatens early wins only through a narrow draw, that should appear as low-confidence or conditional speed.

## Interaction

Interaction measures how well the deck can stop other players from winning and protect its own plan.

Primary inputs:

- Instant-speed creature removal.
- Artifact and enchantment answers.
- Stack interaction.
- Graveyard hate.
- Board wipes.
- Protection pieces.
- Stax or tax effects.
- Mana efficiency of answers.
- Coverage across common Commander threat types.

Interaction should distinguish broad coverage from raw count. Ten narrow removal spells are not equivalent to a balanced answer suite.

## Consistency

Consistency measures how reliably the deck executes its intended plan.

Primary inputs:

- Land count and color source quality.
- Curve fit against the mana base.
- Card draw and card selection.
- Tutor density.
- Redundancy for key effects.
- Commander dependency.
- Dead-card risk.
- Mulligan and opening-hand heuristics.
- Internal tension between card packages.
- Opening-hand simulation, land-drop rates, curve-hit rates, and commander-cast timing where feasible.

Consistency should penalize decks that contain powerful cards but cannot reliably cast or find them.

## Pod Fit

Pod fit measures whether 2 to 4 Commander decks are likely to produce a satisfying game together.

Primary inputs:

- Power score spread.
- Speed score spread.
- Interaction distribution.
- Combo, stax, extra-turn, and mass-land-denial flags.
- Commander dependency and removal pressure.
- Likely archenemy or pubstomp risk.
- Durdle risk where a deck cannot meaningfully participate.
- Social friction flags for Rule 0 discussion.

Pod fit should produce a practical brief, not just a number. The brief should explain likely mismatch patterns and suggest swaps or expectations.

## Collection-Aware Tuning

Collection-aware tuning is not a score by itself. It is a recommendation layer that uses the user's owned cards and deck library demand to make advice more actionable.

Primary inputs:

- Owned versus missing cards in the analyzed deck.
- Cards needed by multiple decks.
- Owned cards that fit the deck color identity and role needs.
- Missing role coverage such as ramp, draw, interaction, wipes, protection, and win conditions.
- Optional price snapshots when available, clearly marked as stale-prone context.

Collection-aware recommendations should distinguish "you already own this", "this fills a structural need", "this answers your recorded meta", and "this is merely a possible buy." The app must not imply a purchase is required to make a deck valid or fun.

## Real Meta Evidence

Recorded playgroup history can improve tuning but must not overwrite deterministic deck facts.

Primary inputs:

- Deck win rate, games played, draws, average turns, and last played.
- Commander appearances, wins, average score band, and matchup notes.
- Pod balance history and mismatch outcomes.
- Win-condition breakdowns.
- Recurring salt, stax, combo, speed, or interaction complaints recorded in notes or post-game reviews.
- Revision performance before and after deck changes.

Meta evidence should include sample size and recency. A single game should create prompts and questions, not confident conclusions.

## Rubric Versioning

The initial rubric version is `2026-05-03.phase0`.

Future rubric changes must be versioned. Existing analysis runs should keep their original rubric version so old scorecards remain auditable.
