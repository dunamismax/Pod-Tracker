# Analysis Rubric

Ideal Magic scores Commander decks and pods from deterministic evidence first. AI evaluation may refine explanations and judgment later, but every score must remain traceable to stored facts, rubric versions, and source data.

Scores are stored internally on a 0-100 scale and displayed with plain-language bands. The bands are intentionally broad at v1 because Commander power varies by local meta.

## Score Bands

- 0-19: Nonfunctional or illegal for the requested context.
- 20-39: Very low power, inconsistent, or heavily constrained.
- 40-54: Casual or precon-like.
- 55-69: Tuned casual or upgraded precon.
- 70-84: Optimized or high-power.
- 85-100: cEDH-like speed, density, resilience, or combo pressure.

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
