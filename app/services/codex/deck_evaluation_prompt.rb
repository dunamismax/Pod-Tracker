module Codex
  class DeckEvaluationPrompt
    PROMPT_VERSION = "deck-eval-v1".freeze

    def call(deck, analysis_run: nil)
      run = analysis_run || deck.latest_deterministic_run
      scorecard = run&.scorecard
      raise ArgumentError, "Deck evaluation prompt requires a deterministic run with a scorecard" unless run && scorecard

      input = {
        "deck" => deck_payload(deck),
        "deterministic_facts" => deterministic_facts(run, scorecard),
        "rubric" => rubric_payload,
        "response_contract" => response_contract
      }

      {
        "prompt_version" => PROMPT_VERSION,
        "schema_version" => ScorecardResponseSchema::VERSION,
        "response_schema" => ScorecardResponseSchema.to_h,
        "input" => input,
        "messages" => messages(input)
      }
    end

    private

    def deck_payload(deck)
      cards = deck.deck_cards
                  .where(board: %w[commander main])
                  .order(:board, :position, :id)
                  .map do |card|
        {
          "board" => card.board,
          "quantity" => card.quantity,
          "name" => card.name,
          "type_line" => card.oracle_card&.type_line,
          "mana_value" => card.oracle_card&.mana_value
        }.compact
      end

      {
        "id" => deck.id,
        "name" => deck.name,
        "format" => deck.format,
        "commanders" => deck.commander_names,
        "cards" => cards
      }
    end

    def deterministic_facts(run, scorecard)
      bracket = scorecard.bracket_payload.is_a?(Hash) ? scorecard.bracket_payload : {}
      feature_vector = run.feature_vector.is_a?(Hash) ? run.feature_vector : {}
      evidence = scorecard.evidence.is_a?(Hash) ? scorecard.evidence : {}
      legality = run.deterministic_snapshot.is_a?(Hash) ? run.deterministic_snapshot["legality"] : nil

      facts = []
      facts << fact("fact.deck.card_count", "Deck contains #{feature_vector['total_cards'].to_i} Commander-relevant cards.", feature_vector.slice("total_cards", "nonland_count", "land_count"))
      facts << fact("fact.deck.commanders", "Commanders: #{Array(run.deck&.commander_names).join(', ')}.", "commanders" => Array(run.deck&.commander_names))
      facts << fact("fact.bracket.headline", bracket["headline"].presence || "Bracket #{scorecard.bracket}", bracket.slice("bracket", "label", "sub_band", "expected_min_turn", "headline"))
      facts << fact("fact.bracket.game_changers", "#{Array(bracket['game_changers']).size} Game Changer card(s) detected.", "game_changers" => Array(bracket["game_changers"]))
      facts << fact("fact.bracket.combo_pairs", "#{Array(bracket['combo_pairs']).size} two-card combo candidate(s) detected.", "combo_pairs" => Array(bracket["combo_pairs"]))
      facts << fact("fact.legality.result", legality ? "Commander legality is #{legality['legal'] ? 'legal' : 'not legal'}." : "Commander legality unavailable.", legality || {})

      score_facts(scorecard).each { |item| facts << item }
      feature_facts(feature_vector).each { |item| facts << item }
      evidence_facts(evidence).each { |item| facts << item }
      facts
    end

    def score_facts(scorecard)
      {
        "power" => scorecard.power_score,
        "speed" => scorecard.speed_score,
        "interaction" => scorecard.interaction_score,
        "consistency" => scorecard.consistency_score,
        "salt" => scorecard.salt_score,
        "social_friction" => scorecard.social_friction_score
      }.map do |axis, value|
        fact("fact.score.#{axis}", "Deterministic #{axis.tr('_', ' ')} score is #{value}/10.", "axis" => axis, "value" => value)
      end
    end

    def feature_facts(feature_vector)
      role_counts = feature_vector.fetch("role_counts", {})
      salt_counts = feature_vector.fetch("salt_counts", {})
      friction_counts = feature_vector.fetch("friction_counts", {})

      [
        fact("fact.features.roles", "Role counts include ramp, fast mana, tutors, draw, interaction, and combo markers.", role_counts),
        fact("fact.features.salt", "Salt-driver counts from curated deterministic tags.", salt_counts),
        fact("fact.features.friction", "Social-friction counts from curated deterministic tags.", friction_counts),
        fact("fact.features.mana_curve", "Mana curve and color requirements from source-backed card data.", feature_vector.slice("mana_curve", "color_pip_counts", "commander_color_identity", "mana_source_count"))
      ]
    end

    def evidence_facts(evidence)
      ScorecardResponseSchema::AXES.filter_map do |axis|
        axis_evidence = evidence.dig(axis, "evidence") || evidence[axis]
        next if axis_evidence.blank?

        fact("fact.evidence.#{axis}", "Deterministic evidence for #{axis.tr('_', ' ')}.", axis_evidence)
      end
    end

    def rubric_payload
      {
        "primary_axis" => "Official Commander Bracket placement remains the headline. Do not override legality or bracket gates.",
        "adjustment_policy" => "Return small score adjustments from -2 to 2 only when the decklist context justifies them beyond deterministic tags.",
        "axes" => {
          "power" => "Ability to win against prepared Commander tables.",
          "speed" => "How quickly the deck threatens a win or dominant board.",
          "interaction" => "How well it answers threats and protects its plan.",
          "consistency" => "How reliably it executes its plan.",
          "salt" => "Likelihood of frustrating a typical table.",
          "social_friction" => "How much Rule 0 conversation the deck needs."
        }
      }
    end

    def response_contract
      {
        "schema_version" => ScorecardResponseSchema::VERSION,
        "must_cite_fact_ids" => true,
        "fact_ref_format" => "fact.*",
        "uncertainty_required" => true,
        "output" => "Return only valid JSON matching the supplied schema."
      }
    end

    def messages(input)
      [
        {
          "role" => "system",
          "content" => "You are evaluating a Magic: The Gathering Commander deck for Ideal Magic. Deterministic facts are authoritative. Cite fact IDs for every adjustment, driver, talking point, and recommendation. Mark uncertainty instead of inventing missing card facts. Return only JSON."
        },
        {
          "role" => "user",
          "content" => JSON.pretty_generate(input)
        }
      ]
    end

    def fact(id, text, data)
      { "id" => id, "text" => text, "data" => data }
    end
  end
end
