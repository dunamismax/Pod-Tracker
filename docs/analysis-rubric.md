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

## Rubric Versioning

The initial rubric version is `2026-05-03.phase0`.

Future rubric changes must be versioned. Existing analysis runs should keep their original rubric version so old scorecards remain auditable.

