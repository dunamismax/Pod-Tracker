module Codex
  # Builds the v2 deck-evaluation payload. Unlike the v1 adjustment-only
  # prompt, the AI is now asked to make the bracket call and the six
  # 0-10 axis calls itself, after being shown the long-form bracket
  # rules text, the canonical Game Changers list, and the Commander
  # banlist. Deterministic feature signals are still included as
  # context but are no longer the authority.
  #
  # The prompt is built so the LLM can reason for as long as it needs
  # — Codex App Server runs are queued and rendered once they finish,
  # so a multi-minute response is acceptable.
  class DeckEvaluationPrompt
    PROMPT_VERSION = "deck-eval-v2".freeze

    def call(deck, analysis_run: nil)
      run = analysis_run || deck.latest_deterministic_run
      input = {
        "task" => task_description,
        "deck" => deck_payload(deck),
        "context" => BracketBriefing.payload,
        "deterministic_signals" => deterministic_signals(deck, run),
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
        "Place this deck on the official Commander Brackets (1 Exhibition · 2 Core · 3 Upgraded · 4 Optimized · 5 cEDH).",
        "Sub-band the placement low/mid/high based on how the deck plays inside its bracket.",
        "Score the six 0-10 axes (power, speed, interaction, consistency, salt, social_friction) using the anchor bands provided.",
        "Use the Commander banlist for legality. Use the Game Changers list to count GCs. Apply the bracket gates exactly.",
        "Cite the specific cards in this decklist that drove each call. Do not invent cards.",
        "Take as much time as you need; this is a queued background evaluation, not an interactive turn.",
        "Return one JSON object that matches the supplied response schema. No prose around the JSON."
      ].join(" ")
    end

    def deck_payload(deck)
      cards = deck.deck_cards
                  .where(board: %w[commander main])
                  .includes(:oracle_card)
                  .order(:board, :position, :id)
                  .map do |card|
        {
          "board" => card.board,
          "quantity" => card.quantity,
          "name" => card.name,
          "type_line" => card.oracle_card&.type_line,
          "mana_value" => card.oracle_card&.mana_value,
          "mana_cost" => card.oracle_card&.mana_cost
        }.compact
      end

      {
        "id" => deck.id,
        "name" => deck.name,
        "format" => deck.format,
        "commanders" => deck.commander_names,
        "card_count" => cards.sum { |c| c["quantity"].to_i },
        "cards" => cards
      }
    end

    def deterministic_signals(deck, run)
      return { "available" => false, "note" => "No deterministic feature extraction has run for this deck. Rely on the supplied decklist." } if run.nil?

      scorecard = run.scorecard
      feature_vector = run.feature_vector.is_a?(Hash) ? run.feature_vector : {}
      legality = run.deterministic_snapshot.is_a?(Hash) ? run.deterministic_snapshot["legality"] : nil

      {
        "available" => true,
        "rubric_version" => run.rubric_version,
        "summary" => "Deterministic feature counts and tag-driven evidence. Useful as a sanity check; the AI is the authority for the final call.",
        "feature_vector" => feature_vector,
        "deterministic_scorecard" => scorecard ? deterministic_scorecard_payload(scorecard) : nil,
        "legality" => legality
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

    def response_contract
      {
        "schema_version" => DeckEvaluationSchema::VERSION,
        "must_match_schema" => true,
        "rules" => [
          "Return only one JSON object. No code fences. No prose around the JSON.",
          "bracket.value must be an integer 1..5 corresponding to the matched bracket.",
          "sub_band must be 'low', 'mid', or 'high'.",
          "Each axis must include an integer value 0..10, a rationale, and an evidence array of cards or patterns from this decklist.",
          "Use the uncertainty arrays to flag thin signal rather than guessing.",
          "Restrictions must list the bracket's gates with status ok / ok_singleton / absent / any_allowed / present_allowed / violation.",
          "If you find a banned card, flag it under legality_review.flagged_cards and explain in legality_review.note. Do not lower the bracket on banned cards alone.",
          "Headlines and taglines should be reusable as a Rule 0 opener."
        ]
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
        "You produce one JSON object that follows the supplied schema exactly.",
        "You apply the published Commander Brackets gates strictly: a deck cannot be Bracket 3 if it has more than 3 Game Changers, runs mass land denial, chains extra turns, or can find a two-card game-ending combo before turn 6.",
        "You apply the Commander banlist as the legality authority. The Game Changers list is descriptive, not a ban list.",
        "You sub-band low/mid/high using how the deck plays inside its bracket — a tuned Bracket 3 trending into Bracket 4 is high; a precon-class Bracket 3 is low.",
        "You cite the specific cards from the supplied decklist that drove each call. You do not invent cards.",
        "You may take as long as needed to think; the response is rendered after this run completes."
      ].join(" ")
    end
  end
end
