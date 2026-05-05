module Pods
  class RuleZeroBrief
    # Power bands stay around for sub-band labelling, but the bracket aggregate
    # is the headline. Sub-band power talk goes inside the bracket conversation,
    # not in front of it.
    POWER_BANDS = [
      [ 0..3, "Casual / precon" ],
      [ 4..5, "Casual upgraded" ],
      [ 6..7, "Mid-power" ],
      [ 8..8, "High-power" ],
      [ 9..10, "cEDH-adjacent" ]
    ].freeze

    def call(slots, aggregates, warnings, bracket_aggregate = nil)
      {
        "bracket" => bracket_summary(slots, bracket_aggregate),
        "power_band" => power_band(aggregates),
        "speed" => speed_summary(aggregates, bracket_aggregate),
        "interaction" => interaction_summary(aggregates),
        "combo_stax_notes" => combo_stax_notes(slots),
        "salt_notes" => salt_notes(slots, aggregates),
        "friction_notes" => friction_notes(slots, aggregates),
        "headline_warnings" => warnings.first(3).map { |w| w["message"] },
        "pregame_template" => pregame_template(slots, bracket_aggregate)
      }
    end

    private

    def bracket_summary(slots, bracket_aggregate)
      return { "label" => "Unknown", "summary" => "Decks have not been analyzed for brackets yet." } unless bracket_aggregate

      min = bracket_aggregate["min"]
      max = bracket_aggregate["max"]
      gc_total = bracket_aggregate["game_changer_total"].to_i

      summary =
        if min.nil?
          "Bracket data unavailable for this pod."
        elsif min == max
          meta = Decks::BracketEvaluator::BRACKETS[min]
          turn_text = meta["expected_min_turn"] ? "at least #{meta['expected_min_turn']} turns" : "any-turn wins"
          "All decks are Bracket #{min} (#{meta['label']}). Expect a #{meta['label'].downcase} game, #{turn_text}."
        else
          "Decks span Brackets #{min}–#{max}. Treat this as a Rule 0 conversation, not an even pod. The Bracket #{max} deck will move faster than the Bracket #{min} deck — agree on a floor first."
        end

      gc_note = gc_total.zero? ? "No Game Changers across the pod." : "#{gc_total} Game Changer#{'s' unless gc_total == 1} across the pod."

      {
        "label" => bracket_aggregate["headline"],
        "min" => min,
        "max" => max,
        "summary" => summary,
        "game_changers" => gc_note
      }
    end

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
          "Even pod inside #{label.downcase} sub-band (#{min}–#{max})."
        elsif spread <= 2
          "Slight sub-band spread (#{min}–#{max})."
        else
          "Wide sub-band spread (#{min}–#{max})."
        end
      { "label" => label, "summary" => summary, "average" => avg, "min" => min, "max" => max }
    end

    def speed_summary(aggregates, bracket_aggregate = nil)
      speed = aggregates["speed"]
      return { "summary" => "Speed unknown." } unless speed && speed["average"]

      label =
        case speed["average"]
        when 0..3 then "Slow board-build"
        when 4..5 then "Average tempo"
        when 6..7 then "Fast development"
        else "Goldfish-fast"
        end

      turn_hint =
        if bracket_aggregate && bracket_aggregate["max"]
          meta = Decks::BracketEvaluator::BRACKETS[bracket_aggregate["max"]]
          if meta["expected_min_turn"]
            " Bracket #{bracket_aggregate['max']} expects #{meta['expected_min_turn']}+ turns of play."
          else
            " Bracket #{bracket_aggregate['max']} permits any-turn wins."
          end
        else
          ""
        end

      { "label" => label, "average" => speed["average"], "summary" => "Pod averages a #{label.downcase} (#{speed['average']}/10).#{turn_hint}" }
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
        pairs = Array(slot.dig("bracket_payload", "combo_pairs"))
        if pairs.any?
          pairs.map do |pair|
            tail = pair["wins_immediately"] ? " (wins immediately)" : ""
            "#{slot['deck_name']} runs the #{pair['name']} line#{tail} — disclose intended timing."
          end
        else
          combo = slot.dig("feature_vector", "role_counts", "combo").to_i
          combo >= 2 ? [ "#{slot['deck_name']} runs #{combo} combo pieces — disclose intended lines." ] : []
        end
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

    # Produce a copy-pasteable pregame template, slot by slot, in the
    # vocabulary of the official bracket system. This is the headline output
    # of the pod page — players should be able to read it aloud at the table.
    def pregame_template(slots, bracket_aggregate)
      lines = []
      if bracket_aggregate && bracket_aggregate["min"]
        lines <<
          if bracket_aggregate["min"] == bracket_aggregate["max"]
            "Pod target: Bracket #{bracket_aggregate['min']}."
          else
            "Pod target: Brackets #{bracket_aggregate['min']}–#{bracket_aggregate['max']} (mixed — Rule 0 floor required)."
          end
      end

      slots.each do |slot|
        bracket = slot["bracket"]
        next unless bracket

        meta = Decks::BracketEvaluator::BRACKETS[bracket]
        sub = slot["bracket_sub_band"]
        gc_count = Array(slot.dig("bracket_payload", "game_changers")).size
        combo_count = Array(slot.dig("bracket_payload", "combo_pairs")).size
        fast_mana = slot.dig("feature_vector", "role_counts", "fast_mana").to_i
        mld = slot.dig("feature_vector", "salt_counts", "salt_driver_mass_land_denial").to_i
        extra = slot.dig("feature_vector", "salt_counts", "salt_driver_extra_turns").to_i

        flags = []
        flags << "#{gc_count} GC" if gc_count.positive?
        flags << "#{combo_count} two-card combo#{'s' unless combo_count == 1}" if combo_count.positive?
        flags << "#{fast_mana} fast mana" if fast_mana >= 2
        flags << "#{mld} MLD" if mld.positive?
        flags << "#{extra} extra-turn#{'s' unless extra == 1}" if extra.positive?
        flags_text = flags.empty? ? "no headline flags" : flags.join(", ")

        lines << "#{slot['deck_name']}: Bracket #{bracket} #{meta['label']} (#{sub || 'mid'}-band) — #{flags_text}."
      end

      lines.join("\n")
    end
  end
end
