module Codex
  # Builds the pod-evaluation payload (`pod-eval-v3`). Each seated deck
  # gets enriched card data (oracle text, keywords, tags) so the AI can
  # reason about the table, not just commander names. The pod-level
  # response schema (`pod-evaluation-v2`) is unchanged — only prompt
  # input depth evolves. Multi-minute responses are expected.
  class PodEvaluationPrompt
    PROMPT_VERSION = "pod-eval-v3".freeze

    BASIC_LAND_NAMES = DeckEvaluationPrompt::BASIC_LAND_NAMES

    def call(pod, pod_analysis_run: nil)
      run = pod_analysis_run || pod.latest_analysis_run
      raise ArgumentError, "Pod evaluation prompt requires a succeeded pod analysis run" unless run&.status == "succeeded"

      input = {
        "task" => task_description,
        "pod" => pod_payload(pod, run),
        "context" => BracketBriefing.payload,
        "deterministic_pod_analysis" => deterministic_pod_analysis(run),
        "evaluation_protocol" => evaluation_protocol,
        "evidence_quality_bar" => evidence_quality_bar,
        "common_pitfalls" => common_pitfalls,
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
        "You are evaluating a Magic: The Gathering Commander pod for Pod Tracker.",
        "This evaluation is the AUTHORITATIVE pod read on Pod Tracker — your bracket spread, pod-level axes, per-deck table roles, and Rule 0 brief replace the deterministic numbers as the canonical pod analysis.",
        "Review the full pod, not just each deck in isolation. The question is 'will this table feel fair', not 'how strong is each deck'.",
        "Make the authoritative bracket-spread call, six pod-level 0-10 axis calls, per-deck table-role notes, and the Rule 0 brief.",
        "Use the official Commander Brackets, Game Changers list, and Commander banlist supplied in context.",
        "Cite specific decks, commanders, cards, and deterministic warnings that drove each call. Do not invent cards.",
        "Preserve source-backed legality as deterministic truth; use legality concerns only as Rule 0 context.",
        "Walk through the evaluation_protocol steps before scoring. Take as much time as you need; this is a queued background evaluation.",
        "Return one JSON object that matches the supplied response schema exactly. No prose around the JSON."
      ].join(" ")
    end

    def pod_payload(pod, run)
      snapshot_slots = Array(run.snapshot["slots"])
      slots_by_deck_id = snapshot_slots.index_by { |slot| slot["deck_id"].to_i }
      live_slots = pod.pod_slots.includes(deck: [ :commanders, { deck_cards: { oracle_card: :card_tags } } ]).order(:position)

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
        oracle = card.oracle_card
        tags = oracle&.respond_to?(:card_tags) ? oracle.card_tags.map(&:slug).uniq : []
        oracle_text = if BASIC_LAND_NAMES.include?(card.name.to_s)
                        nil
        else
                        oracle&.oracle_text.presence
        end
        {
          "board" => card.board,
          "quantity" => card.quantity,
          "name" => card.name,
          "type_line" => oracle&.type_line,
          "mana_value" => oracle&.mana_value,
          "mana_cost" => oracle&.mana_cost,
          "color_identity" => oracle&.color_identity,
          "keywords" => Array(oracle&.keywords).presence,
          "tags" => tags.presence,
          "oracle_text" => oracle_text
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

    def evaluation_protocol
      {
        "purpose" => "Walk through these steps before scoring the pod. The pod-level numbers should be the conclusion of this analysis, not a guess up front.",
        "steps" => [
          {
            "step" => 1,
            "name" => "Place each deck individually",
            "do" => [
              "For each seated deck: identify the commander, name the archetype, place the bracket, and pick a sub-band — using the same bracket gates as a single-deck review."
            ]
          },
          {
            "step" => 2,
            "name" => "Compute the bracket spread",
            "do" => [
              "Compute min/max/distinct brackets across the table.",
              "Note the spread (max - min). 0 = matched. 1 = stretched. 2+ = mismatched.",
              "Sum Game Changers across the table for the headline GC count."
            ]
          },
          {
            "step" => 3,
            "name" => "Pick a per-deck table role",
            "do" => [
              "Common roles: aggro, midrange, control, combo, group hug, voltron, tribal, stax, big mana, reanimator, storm.",
              "Pick the role that best describes how the deck affects this pod."
            ]
          },
          {
            "step" => 4,
            "name" => "Score pod-level axes (absolute 0-10)",
            "do" => [
              "Pod axes are NOT averages of deck axes. Power = how decisively the strongest deck closes; Speed = how early the fastest deck threatens lethal; Interaction = whether disruption can keep up; Consistency = how often each deck delivers; Salt = expected in-game friction; Social Friction = how much pre-game discussion is needed.",
              "If one deck dominates an axis, the pod axis follows the dominant deck."
            ]
          },
          {
            "step" => 5,
            "name" => "Write the Rule 0 brief",
            "do" => [
              "Headline: one sentence describing the table.",
              "Pregame template: a paste-ready 3-6 sentence brief covering bracket spread, GC count, salt patterns, and pace.",
              "Talking points: 3-5 specific topics the table should disclose before the first turn."
            ]
          },
          {
            "step" => 6,
            "name" => "Friction drivers and recommendations",
            "do" => [
              "Friction drivers: 2-5 entries describing what will produce friction in this pod.",
              "Recommendations: 2-5 concrete swap or pacing suggestions if the pod is mismatched, or 'pod is matched, no changes needed' if it is."
            ]
          }
        ]
      }
    end

    def evidence_quality_bar
      [
        "Cite specific decks by name and specific cards by name. Do not say 'the cEDH deck' — say 'Tymna + Thrasios Thoracle/Consultation'.",
        "Quote concrete numbers: '3 Game Changers in slot 2', 'pod GC total = 6', 'spread Bracket 2 -> Bracket 5'.",
        "If a deterministic warning matches what you observe, cite it; if you disagree, call out the disagreement in uncertainty.",
        "Headlines and Rule 0 prompts must be paste-ready — neutral, descriptive, no jargon."
      ]
    end

    def common_pitfalls
      [
        "Do NOT score pod axes by averaging the deck axes. Pod axes describe the TABLE, not the average deck.",
        "Do NOT call a pod 'mismatched' just because the brackets differ by 1 — that is 'stretched'. Mismatched is a 2+ bracket gap.",
        "Do NOT recommend cuts to a deck that is not in this pod — only suggest swaps for the seated decks or pod-level pacing changes.",
        "Do NOT auto-9 Friction for every cEDH-adjacent pod. A clean Bracket 5 vs Bracket 5 vs Bracket 5 vs Bracket 5 pod can be Friction 4 if everyone is on the same page.",
        "Do NOT echo prompt input keys into the response."
      ]
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
          "axes are pod-level values from 0 to 10. They are not adjustment deltas and they are not averages.",
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
        "You are the Pod Tracker Commander pod evaluator.",
        "Your output is the AUTHORITATIVE pod read on Pod Tracker.",
        "You produce one JSON object that follows the supplied schema exactly.",
        "The pod-level bracket_spread and rule_zero_brief are the authoritative table read once this run succeeds.",
        "You apply the published Commander Brackets gates strictly and use the supplied Game Changers list and banlist.",
        "You score pod-level axes as absolute 0-10 values, not deltas, not deck averages.",
        "You cite actual supplied decks, commanders, cards, and warnings. Do not invent cards.",
        "You may take as long as needed to think; this is rendered after the queued run completes."
      ].join(" ")
    end
  end
end
