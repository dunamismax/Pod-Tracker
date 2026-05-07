module Codex
  class PodEvaluationPrompt
    PROMPT_VERSION = "pod-eval-v2".freeze

    def call(pod, pod_analysis_run: nil)
      run = pod_analysis_run || pod.latest_analysis_run
      raise ArgumentError, "Pod evaluation prompt requires a succeeded pod analysis run" unless run&.status == "succeeded"

      input = {
        "task" => task_description,
        "pod" => pod_payload(pod, run),
        "context" => BracketBriefing.payload,
        "deterministic_pod_analysis" => deterministic_pod_analysis(run),
        "response_contract" => response_contract
      }

      {
        "prompt_version" => PROMPT_VERSION,
        "schema_version" => PodEvaluationSchema::VERSION,
        "response_schema" => PodEvaluationSchema.to_h,
        "input" => input,
        "messages" => messages(input)
      }
    end

    private

    def task_description
      [
        "You are evaluating a Magic: The Gathering Commander pod for Ideal Magic.",
        "Review the full pod, not just each deck in isolation.",
        "Make the authoritative bracket-spread call, six pod-level 0-10 axis calls, per-deck table-role notes, and the Rule 0 brief.",
        "Use the official Commander Brackets, Game Changers list, and Commander banlist supplied in context.",
        "Cite specific decks, commanders, cards, and deterministic warnings that drove each call. Do not invent cards.",
        "Preserve source-backed legality as deterministic truth; use legality concerns only as Rule 0 context.",
        "Return one JSON object that matches the supplied response schema exactly. No prose around the JSON."
      ].join(" ")
    end

    def pod_payload(pod, run)
      snapshot_slots = Array(run.snapshot["slots"])
      slots_by_deck_id = snapshot_slots.index_by { |slot| slot["deck_id"].to_i }
      live_slots = pod.pod_slots.includes(deck: [ :commanders, { deck_cards: :oracle_card } ]).order(:position)

      {
        "id" => pod.id,
        "name" => pod.name,
        "format" => pod.format,
        "slots" => live_slots.map do |slot|
          deck = slot.deck
          snapshot = slots_by_deck_id[deck.id] || {}
          snapshot.slice(
            "position",
            "deck_id",
            "deck_name",
            "commander_names",
            "label",
            "scores",
            "bracket",
            "bracket_sub_band",
            "bracket_payload",
            "feature_vector"
          ).merge(
            "position" => slot.position,
            "label" => slot.label.presence || snapshot["label"],
            "deck_name" => deck.name,
            "commander_names" => deck.commander_names,
            "card_count" => deck.deck_cards.where(board: %w[commander main]).sum(:quantity),
            "cards" => deck_cards_payload(deck)
          )
        end
      }
    end

    def deck_cards_payload(deck)
      deck.deck_cards
          .select { |card| %w[commander main].include?(card.board) }
          .sort_by { |card| [ card.board, card.position || 0, card.id || 0 ] }
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
    end

    def deterministic_pod_analysis(run)
      snapshot = run.snapshot.is_a?(Hash) ? run.snapshot : {}

      {
        "available" => true,
        "rubric_version" => run.rubric_version,
        "summary" => "Deterministic pod analysis, warning generation, and Rule 0 draft. Use as a sanity check; the AI is authoritative for the final pod read once it succeeds.",
        "snapshot" => snapshot.slice("slots", "aggregates", "bracket"),
        "warnings" => Array(run.warnings),
        "rule_zero_brief" => run.rule_zero_brief || {},
        "suggestions" => Array(run.suggestions)
      }
    end

    def response_contract
      {
        "schema_version" => PodEvaluationSchema::VERSION,
        "must_match_schema" => true,
        "rules" => [
          "Return only one JSON object. No code fences. No prose around the JSON.",
          "Top-level keys must be exactly: schema_version, summary, bracket_spread, rule_zero_brief, axes, decks, friction_drivers, recommendations.",
          "bracket_spread describes the whole pod: min/max bracket, spread, distinct brackets, a headline, verdict, rationale, evidence, and uncertainty.",
          "rule_zero_brief must include a paste-ready pregame_template and specific talking_points for this table.",
          "axes are pod-level values from 0 to 10. They are not adjustment deltas.",
          "decks must have one object per seated deck with position, deck_name, commanders, bracket, sub_band, table_role, rationale, evidence, and uncertainty.",
          "Use uncertainty arrays for thin or ambiguous signals. Empty arrays are fine; keys must still be present."
        ],
        "skeleton" => response_skeleton
      }
    end

    def response_skeleton
      {
        "schema_version" => PodEvaluationSchema::VERSION,
        "summary" => "<one paragraph>",
        "bracket_spread" => {
          "min" => 2,
          "max" => 4,
          "spread" => 2,
          "distinct" => [ 2, 3, 4 ],
          "game_changer_total" => 4,
          "headline" => "<short table-fit headline>",
          "verdict" => "<matched, stretched, or mismatched verdict>",
          "rationale" => "<why this pod will or will not feel fair>",
          "evidence" => [ "<deck/card/pattern>" ],
          "uncertainty" => []
        },
        "rule_zero_brief" => {
          "headline" => "<short Rule 0 headline>",
          "pregame_template" => "<paste-ready table brief>",
          "talking_points" => [
            { "topic" => "<topic>", "prompt" => "<question or disclosure>" }
          ],
          "disclosures" => [
            { "label" => "<driver>", "severity" => "moderate", "detail" => "<why>", "evidence" => [] }
          ],
          "uncertainty" => []
        },
        "axes" => PodEvaluationSchema::AXES.index_with do
          {
            "value" => 5,
            "rationale" => "<one or two sentences>",
            "evidence" => [ "<deck/card/pattern>" ],
            "uncertainty" => []
          }
        end,
        "decks" => [
          {
            "position" => 1,
            "deck_name" => "<deck>",
            "commanders" => [ "<commander>" ],
            "bracket" => 3,
            "sub_band" => "mid",
            "table_role" => "<role>",
            "rationale" => "<how this deck shapes the pod>",
            "evidence" => [ "<card/pattern>" ],
            "uncertainty" => []
          }
        ],
        "friction_drivers" => [
          { "label" => "<driver>", "severity" => "moderate", "explanation" => "<why>", "evidence" => [] }
        ],
        "recommendations" => [
          { "category" => "pod", "title" => "<short>", "detail" => "<one or two sentences>" }
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
        "You are the Ideal Magic Commander pod evaluator.",
        "You produce one JSON object that follows the supplied schema exactly.",
        "The pod-level bracket_spread and rule_zero_brief are the authoritative table read once this run succeeds.",
        "You apply the published Commander Brackets gates strictly and use the supplied Game Changers list and banlist.",
        "You score pod-level axes as absolute 0-10 values, not deltas.",
        "You cite actual supplied decks, commanders, cards, and warnings. Do not invent cards.",
        "You may take as long as needed to think; this is rendered after the queued run completes."
      ].join(" ")
    end
  end
end
