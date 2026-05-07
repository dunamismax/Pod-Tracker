module Codex
  class PodEvaluationPrompt
    PROMPT_VERSION = "pod-eval-v1".freeze

    def call(pod, pod_analysis_run: nil)
      run = pod_analysis_run || pod.latest_analysis_run
      raise ArgumentError, "Pod evaluation prompt requires a succeeded pod analysis run" unless run&.status == "succeeded"

      input = {
        "pod" => pod_payload(pod, run),
        "deterministic_facts" => deterministic_facts(run),
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

    def pod_payload(pod, run)
      {
        "id" => pod.id,
        "name" => pod.name,
        "format" => pod.format,
        "slots" => Array(run.snapshot["slots"]).map do |slot|
          slot.slice(
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
          )
        end
      }
    end

    def deterministic_facts(run)
      snapshot = run.snapshot.is_a?(Hash) ? run.snapshot : {}
      slots = Array(snapshot["slots"])
      aggregates = snapshot.fetch("aggregates", {})
      bracket = snapshot.fetch("bracket", {})

      facts = []
      facts << fact("fact.pod.size", "Pod has #{slots.size} deck slot(s).", "slot_count" => slots.size)
      facts << fact("fact.pod.bracket", bracket["headline"].presence || "Bracket data unavailable.", bracket)
      ScorecardResponseSchema::AXES.each do |axis|
        aggregate = aggregates[axis]
        facts << fact("fact.pod.aggregate.#{axis}", "Pod #{axis.tr('_', ' ')} aggregate.", aggregate || {})
      end

      slots.each_with_index do |slot, idx|
        slot_ref = "slot#{idx + 1}"
        facts << fact("fact.pod.#{slot_ref}.identity", "#{slot['deck_name']} commanded by #{Array(slot['commander_names']).join(', ')}.", slot.slice("deck_name", "commander_names", "label"))
        facts << fact("fact.pod.#{slot_ref}.scores", "#{slot['deck_name']} deterministic scores.", slot["scores"] || {})
        facts << fact("fact.pod.#{slot_ref}.bracket", "#{slot['deck_name']} bracket placement.", slot.slice("bracket", "bracket_sub_band", "bracket_payload"))
        facts << fact("fact.pod.#{slot_ref}.features", "#{slot['deck_name']} feature vector.", slot["feature_vector"] || {})
      end

      facts << fact("fact.pod.warnings", "#{Array(run.warnings).size} deterministic warning(s) generated.", Array(run.warnings))
      facts << fact("fact.pod.rule_zero_brief", "Deterministic Rule 0 brief generated for the pod.", run.rule_zero_brief)
      facts
    end

    def rubric_payload
      {
        "primary_axis" => "The pod bracket headline and deterministic warnings remain authoritative.",
        "task" => "Explain table-fit issues, Rule 0 talking points, and small score adjustments per pod context.",
        "adjustment_policy" => "Return adjustments from -2 to 2 only when the full pod context changes how an axis should be read.",
        "axes" => ScorecardResponseSchema::AXES
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
          "content" => "You are evaluating a Commander pod for Ideal Magic. Deterministic pod analysis is authoritative. Cite fact IDs for every adjustment, driver, talking point, and recommendation. Mark uncertainty instead of inventing hidden deck intent. Return only JSON."
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
