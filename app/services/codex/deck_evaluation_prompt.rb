module Codex
  # Builds the deck-evaluation payload (`deck-eval-v3`). The AI is shown
  # the long-form bracket rules, the canonical Game Changers list, the
  # Commander banlist, the per-axis scoring playbook, and a card-by-card
  # decklist enriched with oracle text, keywords, color identity, and
  # Ideal Magic's role/salt/friction tag slugs. It is asked to make the
  # bracket call, sub-band call, the six 0-10 axis calls, friction
  # drivers, Rule 0 talking points, and concrete recommendations itself.
  #
  # The schema (`deck-evaluation-v2`) is unchanged — only the prompt
  # input shape and the depth of guidance evolve. Codex App Server runs
  # are queued and rendered once they finish, so a multi-minute
  # response is acceptable.
  class DeckEvaluationPrompt
    PROMPT_VERSION = "deck-eval-v3".freeze

    BASIC_LAND_NAMES = %w[Plains Island Swamp Mountain Forest Wastes
                          Snow-Covered\ Plains Snow-Covered\ Island Snow-Covered\ Swamp
                          Snow-Covered\ Mountain Snow-Covered\ Forest].freeze

    def call(deck, analysis_run: nil)
      run = analysis_run || deck.latest_deterministic_run
      input = {
        "task" => task_description,
        "deck" => deck_payload(deck),
        "context" => BracketBriefing.payload,
        "deterministic_signals" => deterministic_signals(deck, run),
        "evaluation_protocol" => evaluation_protocol,
        "evidence_quality_bar" => evidence_quality_bar,
        "common_pitfalls" => common_pitfalls,
        "output_quality_checklist" => output_quality_checklist,
        "response_contract" => response_contract
      }

      {
        "prompt_version" => PROMPT_VERSION,
        "schema_version" => DeckEvaluationSchema::VERSION,
        "response_schema" => DeckEvaluationSchema.to_h,
        "input" => input,
        "messages" => messages(input)
      }
    end

    private

    def task_description
      [
        "You are evaluating a Magic: The Gathering Commander deck for Ideal Magic.",
        "This evaluation is the AUTHORITATIVE bracket and power-band read for this deck on Ideal Magic — the user will see your bracket call, your six 0-10 axis values, your evidence, and your Rule 0 talking points as the canonical analysis. Treat this as a careful bracket review, not a quick take.",
        "Place this deck on the official Commander Brackets (1 Exhibition · 2 Core · 3 Upgraded · 4 Optimized · 5 cEDH). Sub-band the placement low/mid/high based on how the deck plays inside its bracket.",
        "Score the six 0-10 axes (power, speed, interaction, consistency, salt, social_friction) against the absolute anchor bands provided. A 7 means the same thing across brackets — the bracket only changes how often a deck reaches that band.",
        "Use the Commander banlist for legality. Use the Game Changers list to count GCs. Apply the bracket gates exactly.",
        "Cite the specific cards in this decklist that drove each call. Do not invent cards. If you cannot tell from the decklist what something does, prefer to flag uncertainty rather than guess.",
        "Walk through the evaluation_protocol step-by-step before scoring. Quality of evidence matters more than confidence.",
        "Take as much time as you need; this is a queued background evaluation, not an interactive turn. Multi-minute responses are expected and welcome.",
        "Return one JSON object that matches the supplied response schema EXACTLY — same keys, same nesting, same field names. Do not echo prompt input keys (deck_id, deck_name, format) into the response. No prose around the JSON."
      ].join(" ")
    end

    def deck_payload(deck)
      cards = deck.deck_cards
                  .where(board: %w[commander main])
                  .includes(oracle_card: :card_tags)
                  .order(:board, :position, :id)
      composition = composition_overview(cards)

      {
        "id" => deck.id,
        "name" => deck.name,
        "format" => deck.format,
        "commanders" => deck.commander_names,
        "card_count" => cards.sum(&:quantity),
        "composition_overview" => composition,
        "cards" => cards.map { |card| card_payload(card) }
      }
    end

    def card_payload(card)
      oracle = card.oracle_card
      payload = {
        "board" => card.board,
        "quantity" => card.quantity,
        "name" => card.name,
        "type_line" => oracle&.type_line,
        "mana_value" => oracle&.mana_value,
        "mana_cost" => oracle&.mana_cost,
        "color_identity" => oracle&.color_identity,
        "colors" => oracle&.colors,
        "keywords" => Array(oracle&.keywords).presence,
        "edhrec_rank" => oracle&.edhrec_rank,
        "tags" => card_tags_for(oracle),
        "oracle_text" => oracle_text_for(card, oracle)
      }
      payload.compact
    end

    def card_tags_for(oracle)
      return nil unless oracle&.respond_to?(:card_tags)
      slugs = oracle.card_tags.map(&:slug).uniq
      slugs.presence
    end

    def oracle_text_for(card, oracle)
      return nil if BASIC_LAND_NAMES.include?(card.name.to_s)
      text = oracle&.oracle_text
      return nil if text.blank?
      text
    end

    def composition_overview(cards)
      total = cards.sum(&:quantity)
      lands = cards.select { |c| c.oracle_card&.type_line.to_s.downcase.include?("land") }.sum(&:quantity)
      basics = cards.select { |c| BASIC_LAND_NAMES.include?(c.name.to_s) }.sum(&:quantity)
      {
        "total_cards" => total,
        "land_count" => lands,
        "basic_land_count" => basics,
        "nonland_count" => [ total - lands, 0 ].max,
        "color_identity" => color_identity_for(cards),
        "mana_value_buckets" => mana_value_buckets(cards),
        "type_breakdown" => type_breakdown(cards)
      }
    end

    def color_identity_for(cards)
      identity = cards.flat_map { |c| Array(c.oracle_card&.color_identity) }
      identity.uniq.sort
    end

    def mana_value_buckets(cards)
      buckets = { "0" => 0, "1" => 0, "2" => 0, "3" => 0, "4" => 0, "5" => 0, "6+" => 0 }
      cards.each do |card|
        next if card.oracle_card&.type_line.to_s.downcase.include?("land")
        mv = card.oracle_card&.mana_value.to_f
        bucket = mana_value_bucket_for(mv)
        buckets[bucket] += card.quantity
      end
      buckets
    end

    def mana_value_bucket_for(mv)
      return "6+" if mv >= 6
      return "5" if mv >= 5
      return "4" if mv >= 4
      return "3" if mv >= 3
      return "2" if mv >= 2
      return "1" if mv >= 1
      "0"
    end

    def type_breakdown(cards)
      counts = Hash.new(0)
      cards.each do |card|
        type_line = card.oracle_card&.type_line.to_s
        primary = primary_type_for(type_line)
        counts[primary] += card.quantity
      end
      counts
    end

    def primary_type_for(type_line)
      return "unknown" if type_line.blank?
      lower = type_line.downcase
      return "land" if lower.include?("land")
      return "creature" if lower.include?("creature")
      return "planeswalker" if lower.include?("planeswalker")
      return "battle" if lower.include?("battle")
      return "artifact" if lower.include?("artifact")
      return "enchantment" if lower.include?("enchantment")
      return "instant" if lower.include?("instant")
      return "sorcery" if lower.include?("sorcery")
      "other"
    end

    def deterministic_signals(deck, run)
      return { "available" => false, "note" => "No deterministic feature extraction has run for this deck. Rely on the supplied decklist alone." } if run.nil?

      scorecard = run.scorecard
      feature_vector = run.feature_vector.is_a?(Hash) ? run.feature_vector : {}
      legality = run.deterministic_snapshot.is_a?(Hash) ? run.deterministic_snapshot["legality"] : nil

      {
        "available" => true,
        "rubric_version" => run.rubric_version,
        "summary" => "Deterministic feature counts and tag-driven evidence from Ideal Magic's source-controlled card taxonomy. Treat these as a sanity check — useful for cross-checking what you see in the decklist, not as authority. You make the bracket and the six axis calls.",
        "feature_vector" => feature_vector,
        "deterministic_scorecard" => scorecard ? deterministic_scorecard_payload(scorecard) : nil,
        "legality" => legality,
        "use_as" => [
          "Cross-check tutor / fast-mana / wipe / counter / extra-turn / mass-land-denial / combo counts before scoring.",
          "If your read disagrees with the deterministic counts, prefer your own decklist read — but call out the disagreement in the relevant axis uncertainty array.",
          "Quote the deterministic counts in evidence when they support a call (e.g. 'feature_vector reports 6 fast_mana sources')."
        ]
      }.compact
    end

    def deterministic_scorecard_payload(scorecard)
      {
        "bracket" => scorecard.bracket,
        "bracket_sub_band" => scorecard.bracket_sub_band,
        "bracket_payload" => scorecard.bracket_payload,
        "axes" => DeckEvaluationSchema::AXES.index_with do |axis|
          method_name = "#{axis}_score"
          scorecard.respond_to?(method_name) ? scorecard.public_send(method_name) : nil
        end,
        "evidence" => scorecard.evidence,
        "improvement_suggestions" => scorecard.improvement_suggestions
      }
    end

    # Step-by-step structure the LLM should walk through before producing
    # the final JSON. This is the single biggest lever for axis-score
    # quality — the LLM tends to skip straight to numbers without
    # reading the decklist.
    def evaluation_protocol
      {
        "purpose" => "Walk through these steps before scoring. The axis values you produce should be the conclusion of this analysis, not a guess up front.",
        "steps" => [
          {
            "step" => 1,
            "name" => "Read the commander identity",
            "do" => [
              "Identify the commander(s) and what they reward.",
              "Name the deck's archetype in one phrase: aggro, midrange, control, combo, group hug, voltron, tribal, stax, big mana, reanimator, storm, lands, etc.",
              "Note color identity and what it implies for mana base quality."
            ]
          },
          {
            "step" => 2,
            "name" => "Walk the mana base",
            "do" => [
              "Land count, basic count, ratio of fetches/duals/shocks/tap-lands.",
              "Count fast mana (Sol Ring, Mana Crypt, Mana Vault, the Moxen, Lotus Petal, Jeweled Lotus, Ancient Tomb, City of Traitors).",
              "Count ramp pieces — distinguish 1-drop ramp (Sol Ring, signets, talismans) from 2-drop sorcery ramp (Cultivate, Rampant Growth) from creature ramp (Birds of Paradise)."
            ]
          },
          {
            "step" => 3,
            "name" => "Identify the win condition(s) and the path",
            "do" => [
              "Name each plausible win line in one sentence.",
              "For each, list the cards that participate and the mana/turns to assemble it.",
              "Flag two-card combos (Thoracle+Consultation, Dramatic Reversal+Isochron Scepter, Heliod+Walking Ballista, Mike+Trike, Kiki+Felidar/Pestermite).",
              "Flag alternate-win cards (Thoracle, Lab Maniac, Approach of the Second Sun, Maze's End)."
            ]
          },
          {
            "step" => 4,
            "name" => "Catalog the interaction package",
            "do" => [
              "Spot removal, board wipes, counterspells, free counters, hand attack, graveyard hate, hate pieces.",
              "Distinguish instant-speed from sorcery-speed.",
              "Distinguish protection (your own) from interaction (opponents')."
            ]
          },
          {
            "step" => 5,
            "name" => "Catalog draw, tutors, and redundancy",
            "do" => [
              "Count card draw / card selection. Engines (Rhystic Study, Sylvan Library, Necropotence) carry extra weight.",
              "Count tutors. Distinguish unconditional tutors from narrow tutors.",
              "For each role (ramp, draw, removal, win con), count the redundancy."
            ]
          },
          {
            "step" => 6,
            "name" => "Apply bracket gates strictly",
            "do" => [
              "Count Game Changers from the supplied GC list (do not guess; check names).",
              "Look for mass land denial (Armageddon, Ravages of War, Jokulhaups, Wildfire effects, Sunder).",
              "Look for chained or looped extra turns (Time Stretch + Beacon + Alrund's Epiphany; sagas; copy effects).",
              "Look for two-card combos that can be assembled before turn 6 reliably.",
              "Pick the highest bracket whose gates this deck does NOT violate, given its actual build (intent, not aspirational)."
            ]
          },
          {
            "step" => 7,
            "name" => "Score the six axes against the absolute scale",
            "do" => [
              "For each axis: read the axis playbook in context.axes for that key, do the listed counts, pick the anchor band, then nudge inside the band.",
              "Do not adjust an axis to match the bracket call — the axis is on its own scale.",
              "Cite at least 2 specific cards or patterns per axis in evidence (or, for thin signal, 1 + an uncertainty entry)."
            ]
          },
          {
            "step" => 8,
            "name" => "Sub-band the bracket",
            "do" => [
              "low = barely qualifies; could play down a bracket on a soft night.",
              "mid = sits squarely inside the bracket.",
              "high = pushes the upper edge; could pass for next bracket if a couple of cards changed."
            ]
          },
          {
            "step" => 9,
            "name" => "Produce friction drivers, Rule 0 talking points, and recommendations",
            "do" => [
              "Friction drivers: 2-5 entries describing what this deck makes opponents feel. Severity is low/moderate/high.",
              "Rule 0 talking points: 2-5 short sentences a player can read out loud at the table — disclosures, expected pace, expected lines.",
              "Recommendations: 3-6 concrete tuning ideas (cut/swap/add specific cards) calibrated to keep the deck inside its bracket OR to push it up to the next bracket if the user wants to."
            ]
          }
        ]
      }
    end

    def evidence_quality_bar
      [
        "Every axis evidence array should cite at least one specific card or named pattern from the supplied decklist. Two or more is better.",
        "Prefer concrete numbers over adjectives: '5 fast-mana sources' beats 'lots of fast mana'; 'goldfishes turn 4' beats 'fast'.",
        "Quote turn timings when relevant ('combo lands turn 4 on Sol Ring open', 'wipe at turn 3 on Toxic Deluge').",
        "If a tag in deterministic_signals.feature_vector.evidence_by_tag matches a real card in the decklist, prefer the card name in your evidence.",
        "When you flag uncertainty, name what is missing or thin. 'Pod meta unknown' is fine; 'unsure' is not.",
        "Headlines and taglines should be reusable as a Rule 0 opener — short, neutral, descriptive."
      ]
    end

    def common_pitfalls
      [
        "Do NOT score Salt high just because the deck has counterspells. Counterspells are Interaction.",
        "Do NOT conflate Power and Speed. A deck can be 9 Power / 6 Speed (slow control) or 6 Power / 9 Speed (glass-cannon combo).",
        "Do NOT auto-9 Friction for every cEDH deck. A clean Thoracle deck with a known line scores Friction 5-6, not 9. Stax and chaos earn 9.",
        "Do NOT lower the bracket to be polite. If a deck has 4 Game Changers, it cannot be Bracket 3 even if its overall power feels casual.",
        "Do NOT raise the bracket because the deck 'feels' strong. Bracket placement is rules-driven (GCs, MLD, extra turns, two-card combos), not vibes.",
        "Do NOT invent or hallucinate cards. If you don't see a card in the supplied decklist, do not cite it.",
        "Do NOT skip uncertainty arrays. Empty arrays are valid; missing them is not.",
        "Do NOT echo prompt input keys (deck_id, deck_name, format) into the response.",
        "Do NOT collapse all six axes to roughly the same number. If the axes converge, double-check that you're using the absolute scale."
      ]
    end

    def output_quality_checklist
      [
        "Schema_version is exactly '#{DeckEvaluationSchema::VERSION}'.",
        "Top-level keys are exactly: schema_version, summary, bracket, axes, friction_drivers, rule_zero_talking_points, recommendations, and optionally legality_review.",
        "Bracket has value (1-5), label, sub_band (low/mid/high), headline, tagline, restrictions (with status from the allowed enum), evidence, uncertainty.",
        "Each of the six axes has value (0-10), rationale, evidence (array), uncertainty (array). All four keys are present.",
        "Friction drivers, Rule 0 talking points, and recommendations are populated (3-5 entries each is the target).",
        "Restrictions list at minimum: Game Changers, Mass Land Denial, Extra Turns, Two-Card Combos. Legality is allowed but not required there.",
        "Evidence cites real cards from the decklist.",
        "Numbers fall in valid ranges (axis 0-10, bracket 1-5)."
      ]
    end

    def response_contract
      {
        "schema_version" => DeckEvaluationSchema::VERSION,
        "must_match_schema" => true,
        "rules" => [
          "Return only one JSON object. No code fences. No prose around the JSON.",
          "Top-level keys must be exactly: schema_version, summary, bracket, axes, friction_drivers, rule_zero_talking_points, recommendations, and optionally legality_review. Do not add deck_id, deck_name, format, game_changers, restrictions, key_evidence, or evidence at the top level — those belong inside bracket.",
          "bracket is an object with these keys ONLY: value, label, sub_band, expected_min_turn (or null), headline, tagline, restrictions, game_changers, evidence, uncertainty. Do not add a 'rationale' key inside bracket — its content goes in headline + tagline + evidence.",
          "bracket.value must be an integer 1..5 corresponding to the matched bracket.",
          "bracket.sub_band must be 'low', 'mid', or 'high'.",
          "bracket.restrictions must be an array of objects { label, status, detail, evidence? }, where status is one of ok / ok_singleton / absent / any_allowed / present_allowed / violation.",
          "Each axis (power, speed, interaction, consistency, salt, social_friction) is an object with EXACTLY these keys: value (integer 0..10), rationale (string), evidence (array of card/pattern strings), uncertainty (array of strings — empty array allowed but the key must be present).",
          "Use the uncertainty arrays to flag thin signal rather than guessing. Empty arrays are fine; the keys must still be present.",
          "If you find a banned card, flag it under legality_review.flagged_cards (array of card names) and explain in legality_review.note (string). Do not add a 'legal' boolean. Do not lower the bracket on banned cards alone.",
          "Headlines and taglines should be reusable as a Rule 0 opener.",
          "Friction drivers, Rule 0 talking points, and recommendations are optional in the schema but you should populate them — aim for 3-5 entries each."
        ],
        "skeleton" => response_skeleton
      }
    end

    def response_skeleton
      {
        "schema_version" => DeckEvaluationSchema::VERSION,
        "summary" => "<one paragraph describing the deck, its plan, its bracket, and the most important Rule 0 callouts>",
        "bracket" => {
          "value" => 3,
          "label" => "<bracket label>",
          "sub_band" => "mid",
          "expected_min_turn" => nil,
          "headline" => "<short headline>",
          "tagline" => "<short tagline>",
          "restrictions" => [
            { "label" => "Game Changers", "status" => "ok", "detail" => "<count + names + why this satisfies the gate>", "evidence" => [] },
            { "label" => "Mass Land Denial", "status" => "absent", "detail" => "<no MLD found, or list violations>", "evidence" => [] },
            { "label" => "Extra Turns", "status" => "absent", "detail" => "<no chained extra turns / single splashy / chained>", "evidence" => [] },
            { "label" => "Two-Card Combos", "status" => "absent", "detail" => "<no compact combos / found before turn 6 / found after turn 6>", "evidence" => [] }
          ],
          "game_changers" => [
            { "name" => "<card>", "category" => "<category>" }
          ],
          "evidence" => [ "<short bracket-driving note tied to the decklist>" ],
          "uncertainty" => []
        },
        "axes" => DeckEvaluationSchema::AXES.index_with do
          {
            "value" => 5,
            "rationale" => "<one or two sentences anchored to the absolute scale>",
            "evidence" => [ "<card or pattern from the decklist>", "<another card or pattern>" ],
            "uncertainty" => []
          }
        end,
        "friction_drivers" => [
          { "label" => "<driver>", "severity" => "moderate", "explanation" => "<why opponents will feel this>", "evidence" => [] }
        ],
        "rule_zero_talking_points" => [
          { "topic" => "<topic>", "prompt" => "<sentence to read out at the table>" }
        ],
        "recommendations" => [
          { "category" => "tuning", "title" => "<short>", "detail" => "<one or two sentences>", "owned_collection_relevance" => "unknown" }
        ],
        "legality_review" => {
          "note" => "<short legality note>",
          "flagged_cards" => []
        }
      }
    end

    def messages(input)
      [
        {
          "role" => "system",
          "content" => system_message
        },
        {
          "role" => "user",
          "content" => JSON.pretty_generate(input)
        }
      ]
    end

    def system_message
      [
        "You are the Ideal Magic Commander deck evaluator.",
        "Your output is the AUTHORITATIVE bracket and power-band read for this deck on Ideal Magic; the user reads your bracket call, your six axes, your evidence, your friction drivers, and your Rule 0 talking points as the canonical analysis. Take the time to do it well.",
        "You produce one JSON object that follows the supplied schema exactly — match the response_contract.skeleton key-for-key.",
        "Place game_changers, restrictions, evidence, and uncertainty INSIDE the bracket object, not at the top level. Do not echo deck_id / deck_name / format into the response.",
        "Each of the six axes is an object with exactly value, rationale, evidence, uncertainty. Always include uncertainty as an array (empty is fine).",
        "Score axes on the absolute 0-10 scale described in context.axes — a 7 means the same thing across brackets. Do not inflate axis values to justify the bracket call.",
        "Walk the evaluation_protocol steps in order. Cite specific cards from the supplied decklist in your evidence — do not invent cards.",
        "legality_review is optional; if you include it, use { note, flagged_cards } only — do not add a 'legal' boolean.",
        "You apply the published Commander Brackets gates strictly: a deck cannot be Bracket 3 if it has more than 3 Game Changers, runs mass land denial, chains extra turns, or can find a two-card game-ending combo before turn 6.",
        "You apply the Commander banlist as the legality authority. The Game Changers list is descriptive, not a ban list.",
        "You sub-band low/mid/high using how the deck plays inside its bracket — a tuned Bracket 3 trending into Bracket 4 is high; a precon-class Bracket 3 is low.",
        "You may take as long as needed to think; the response is rendered after this run completes. Quality of analysis matters more than speed."
      ].join(" ")
    end
  end
end
