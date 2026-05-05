module Pods
  class SuggestionsBuilder
    # Returns a list of swap suggestions tied to specific decks.
    # Each suggestion: { deck_id, deck_name, category, title, detail }.
    def call(slots, aggregates, _warnings)
      suggestions = []
      power_avg = aggregates.dig("power", "average")
      power_max = aggregates.dig("power", "max").to_i
      power_min = aggregates.dig("power", "min").to_i

      slots.each do |slot|
        scores = slot["scores"] || {}
        deck_id = slot["deck_id"]
        deck_name = slot["deck_name"]
        feature_vector = slot["feature_vector"] || {}
        role_counts = feature_vector["role_counts"] || {}

        # Suggest the high-power deck cuts a few power signals when it's the outlier.
        if scores["power"].to_i >= power_max && power_max - power_min >= 2
          drivers = []
          drivers << "fast mana" if role_counts["fast_mana"].to_i >= 3
          drivers << "tutors" if role_counts["tutor"].to_i >= 4
          drivers << "compact combo" if role_counts["combo"].to_i >= 3
          if drivers.any?
            suggestions << {
              "deck_id" => deck_id,
              "deck_name" => deck_name,
              "category" => "power_down",
              "title" => "Soften the power gap",
              "detail" => "Trim #{drivers.to_sentence} to bring this deck closer to the pod (avg #{power_avg})."
            }
          end
        end

        # Suggest the low-power deck add ramp/draw when it sits below the pod.
        if scores["power"].to_i <= power_min && power_max - power_min >= 2
          if role_counts["ramp"].to_i + role_counts["fast_mana"].to_i < 8
            suggestions << {
              "deck_id" => deck_id,
              "deck_name" => deck_name,
              "category" => "ramp",
              "title" => "Add ramp to keep up",
              "detail" => "Pod averages power #{power_avg}. Lifting ramp/fast-mana count toward 8–12 closes the gap."
            }
          end
          if role_counts["card_draw"].to_i < 8
            suggestions << {
              "deck_id" => deck_id,
              "deck_name" => deck_name,
              "category" => "draw",
              "title" => "Add card draw",
              "detail" => "More draw helps catch faster pods. Aim for 8–12 pieces."
            }
          end
        end

        # Salt above 4 → suggest visible salt cuts.
        if scores["salt"].to_i >= 4
          suggestions << {
            "deck_id" => deck_id,
            "deck_name" => deck_name,
            "category" => "salt",
            "title" => "Consider trimming salt drivers",
            "detail" => "Salt #{scores['salt']}/10. Even one swap on the loudest driver lowers Rule 0 friction."
          }
        end
      end

      suggestions
    end
  end
end
