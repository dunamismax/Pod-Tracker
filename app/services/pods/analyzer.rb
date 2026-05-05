module Pods
  class Analyzer
    RUBRIC_VERSION = "pod-deterministic-v0".freeze

    AXES = %w[power speed interaction consistency salt social_friction].freeze

    Result = Struct.new(:run, keyword_init: true)

    def self.run(pod, user: nil)
      new.run(pod, user: user)
    end

    def run(pod, user: nil)
      raise ArgumentError, "Analyzer requires a persisted pod" unless pod&.persisted?
      slots = pod.pod_slots.includes(deck: :commanders).order(:position).to_a
      raise ArgumentError, "Pod needs at least #{Pod::MIN_SLOTS} slots" if slots.size < Pod::MIN_SLOTS

      ActiveRecord::Base.transaction do
        run = PodAnalysisRun.create!(
          pod: pod,
          user: user || pod.user,
          status: "running",
          rubric_version: RUBRIC_VERSION,
          queued_at: Time.current,
          started_at: Time.current
        )

        slot_payloads = slots.map { |slot| slot_payload(slot) }
        ensure_each_slot_analyzed(slot_payloads, slots)

        aggregates = AXES.index_with { |axis| aggregate_for(slot_payloads, axis) }
        warnings = Pods::WarningGenerator.new.call(slot_payloads, aggregates)
        brief = Pods::RuleZeroBrief.new.call(slot_payloads, aggregates, warnings)
        suggestions = Pods::SuggestionsBuilder.new.call(slot_payloads, aggregates, warnings)

        run.update!(
          status: "succeeded",
          completed_at: Time.current,
          snapshot: {
            "rubric_version" => RUBRIC_VERSION,
            "slots" => slot_payloads,
            "aggregates" => aggregates
          },
          rule_zero_brief: brief,
          warnings: warnings,
          suggestions: suggestions
        )
        pod.update!(status: "analyzed")
        run
      end
    end

    private

    def slot_payload(slot)
      deck = slot.deck
      run = deck.latest_deterministic_run
      sc = run&.scorecard

      {
        "slot_id" => slot.id,
        "position" => slot.position,
        "deck_id" => deck.id,
        "deck_name" => deck.name,
        "commander_names" => deck.commander_names,
        "label" => slot.label,
        "analysis_run_id" => run&.id,
        "scores" => sc ? scorecard_to_h(sc) : nil,
        "feature_vector" => run&.feature_vector || {},
        "rubric_version" => run&.rubric_version
      }
    end

    def ensure_each_slot_analyzed(slot_payloads, slots)
      slot_payloads.each_with_index do |payload, idx|
        next if payload["scores"].present?

        deck = slots[idx].deck
        Decks::Analyzer.run(deck)
        run = deck.reload.latest_deterministic_run
        sc = run&.scorecard
        payload["analysis_run_id"] = run&.id
        payload["scores"] = sc ? scorecard_to_h(sc) : nil
        payload["feature_vector"] = run&.feature_vector || {}
        payload["rubric_version"] = run&.rubric_version
      end
    end

    def scorecard_to_h(sc)
      {
        "power" => sc.power_score,
        "speed" => sc.speed_score,
        "interaction" => sc.interaction_score,
        "consistency" => sc.consistency_score,
        "salt" => sc.salt_score,
        "social_friction" => sc.social_friction_score,
        "confidence" => sc.confidence&.to_f
      }
    end

    def aggregate_for(slot_payloads, axis)
      values = slot_payloads.map { |s| s.dig("scores", axis) }.compact
      return { "average" => nil, "min" => nil, "max" => nil, "spread" => nil, "values" => [], "outliers" => [] } if values.empty?

      avg = (values.sum.to_f / values.size).round(2)
      min = values.min
      max = values.max
      spread = max - min
      outliers = detect_outliers(slot_payloads, axis, avg)

      {
        "average" => avg,
        "min" => min,
        "max" => max,
        "spread" => spread,
        "values" => values,
        "outliers" => outliers
      }
    end

    # An outlier is a score whose distance from the mean is >= 2 points
    # (on the 0..10 scale) AND is the only deck on its side of the gap.
    def detect_outliers(slot_payloads, axis, avg)
      slot_payloads.each_with_object([]) do |slot, memo|
        value = slot.dig("scores", axis)
        next if value.nil?
        delta = (value - avg).round(2)
        next if delta.abs < 2

        memo << {
          "deck_id" => slot["deck_id"],
          "deck_name" => slot["deck_name"],
          "value" => value,
          "delta" => delta,
          "direction" => delta.positive? ? "above" : "below"
        }
      end
    end
  end
end
