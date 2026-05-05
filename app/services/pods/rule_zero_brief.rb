module Pods
  class RuleZeroBrief
    POWER_BANDS = [
      [ 0..3, "Casual / precon" ],
      [ 4..5, "Casual upgraded" ],
      [ 6..7, "Mid-power" ],
      [ 8..8, "High-power" ],
      [ 9..10, "cEDH-adjacent" ]
    ].freeze

    def call(slots, aggregates, warnings)
      {
        "power_band" => power_band(aggregates),
        "speed" => speed_summary(aggregates),
        "interaction" => interaction_summary(aggregates),
        "combo_stax_notes" => combo_stax_notes(slots),
        "salt_notes" => salt_notes(slots, aggregates),
        "friction_notes" => friction_notes(slots, aggregates),
        "headline_warnings" => warnings.first(3).map { |w| w["message"] }
      }
    end

    private

    def power_band(aggregates)
      avg = aggregates.dig("power", "average")
      max = aggregates.dig("power", "max")
      min = aggregates.dig("power", "min")
      return { "label" => "Unknown", "summary" => "Not enough deck analysis to call a band." } if avg.nil?

      band = POWER_BANDS.find { |range, _| range.cover?(avg.round) }
      label = band ? band.last : "Mixed"
      spread = (max - min)
      summary =
        if spread <= 1
          "Even pod around #{label.downcase} (#{min}–#{max})."
        elsif spread <= 2
          "Slight spread inside #{label.downcase} (#{min}–#{max})."
        else
          "Wide spread (#{min}–#{max}). Treat as Rule 0 territory."
        end
      { "label" => label, "summary" => summary, "average" => avg, "min" => min, "max" => max }
    end

    def speed_summary(aggregates)
      speed = aggregates["speed"]
      return { "summary" => "Speed unknown." } unless speed && speed["average"]

      label =
        case speed["average"]
        when 0..3 then "Slow board-build"
        when 4..5 then "Average tempo"
        when 6..7 then "Fast development"
        else "Goldfish-fast"
        end
      { "label" => label, "average" => speed["average"], "summary" => "Pod averages a #{label.downcase} (#{speed['average']}/10)." }
    end

    def interaction_summary(aggregates)
      inter = aggregates["interaction"]
      return { "summary" => "Interaction unknown." } unless inter && inter["average"]

      label =
        case inter["average"]
        when 0..3 then "Light interaction"
        when 4..5 then "Moderate interaction"
        when 6..7 then "Heavy interaction"
        else "Counter-heavy"
        end
      { "label" => label, "average" => inter["average"], "summary" => "Expect #{label.downcase} (#{inter['average']}/10) at the table." }
    end

    def combo_stax_notes(slots)
      combo_callouts = slots.flat_map do |slot|
        combo = slot.dig("feature_vector", "role_counts", "combo").to_i
        next [] if combo < 2

        [ "#{slot['deck_name']} runs #{combo} combo pieces — disclose intended lines." ]
      end

      stax_callouts = slots.flat_map do |slot|
        stax = slot.dig("feature_vector", "role_counts", "stax").to_i
        next [] if stax < 2

        [ "#{slot['deck_name']} runs #{stax} stax pieces — disclose lock plans before turn one." ]
      end

      (combo_callouts + stax_callouts).uniq
    end

    def salt_notes(slots, aggregates)
      salt = aggregates["salt"]
      return [] unless salt && salt["max"].to_i >= 3

      slots.flat_map do |slot|
        score = slot.dig("scores", "salt").to_i
        next [] if score < 3

        [ "#{slot['deck_name']} salt #{score}/10 — surface the loudest drivers (fast mana, MLD, extra turns) up front." ]
      end
    end

    def friction_notes(slots, aggregates)
      friction = aggregates["social_friction"]
      return [] unless friction && friction["max"].to_i >= 3

      slots.flat_map do |slot|
        score = slot.dig("scores", "social_friction").to_i
        next [] if score < 3

        [ "#{slot['deck_name']} friction #{score}/10 — give the table a Rule 0 heads-up before keeping a hand." ]
      end
    end
  end
end
