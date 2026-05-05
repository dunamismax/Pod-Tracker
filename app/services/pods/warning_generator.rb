module Pods
  class WarningGenerator
    # Returns a list of warning hashes:
    #   { "kind" => ..., "severity" => "info|notice|alert", "message" => ..., "decks" => [{"deck_id", "deck_name"}] }
    def call(slots, aggregates)
      warnings = []
      warnings.concat(archenemy_warnings(slots, aggregates))
      warnings.concat(pubstomp_warning(slots, aggregates))
      warnings.concat(durdle_warning(slots, aggregates))
      warnings.concat(salt_mismatch_warning(slots, aggregates))
      warnings.concat(friction_mismatch_warning(slots, aggregates))
      warnings.concat(combo_density_warning(slots))
      warnings
    end

    private

    def archenemy_warnings(slots, aggregates)
      power = aggregates["power"]
      return [] unless power && power["max"]

      top_deck = slots.max_by { |s| s.dig("scores", "power").to_i }
      others_max = slots.reject { |s| s == top_deck }.map { |s| s.dig("scores", "power").to_i }.max.to_i
      gap = top_deck.dig("scores", "power").to_i - others_max
      return [] if gap < 2

      [ {
        "kind" => "archenemy_risk",
        "severity" => gap >= 3 ? "alert" : "notice",
        "message" => "#{top_deck['deck_name']} sits #{gap} power above the next deck. Expect tables to focus it down or feel pubstomped.",
        "decks" => [ deck_ref(top_deck) ]
      } ]
    end

    def pubstomp_warning(slots, aggregates)
      power = aggregates["power"]
      speed = aggregates["speed"]
      return [] unless power && speed
      return [] if power["spread"].to_i < 3 && speed["spread"].to_i < 3
      return [] if power["spread"].to_i < 2

      fast_outliers = (speed["outliers"] || []).select { |o| o["direction"] == "above" }
      power_outliers = (power["outliers"] || []).select { |o| o["direction"] == "above" }
      shared = power_outliers.select { |po| fast_outliers.any? { |so| so["deck_id"] == po["deck_id"] } }
      return [] if shared.empty?

      [ {
        "kind" => "pubstomp_risk",
        "severity" => "alert",
        "message" => "Decks above the pod on both power and speed will close games before slower decks develop.",
        "decks" => shared.map { |o| { "deck_id" => o["deck_id"], "deck_name" => o["deck_name"] } }
      } ]
    end

    def durdle_warning(_slots, aggregates)
      power = aggregates["power"]
      speed = aggregates["speed"]
      return [] unless power && speed
      return [] if power["max"].to_i >= 6 || speed["max"].to_i >= 6
      return [] if power["average"].to_f >= 5 || speed["average"].to_f >= 5

      [ {
        "kind" => "durdle_table",
        "severity" => "info",
        "message" => "Pod skews slow and low-pressure (avg power #{power['average']}, avg speed #{speed['average']}). Plan for long games and bring snacks.",
        "decks" => []
      } ]
    end

    def salt_mismatch_warning(slots, aggregates)
      salt = aggregates["salt"]
      return [] unless salt && salt["spread"].to_i >= 4

      hot = slots.select { |s| s.dig("scores", "salt").to_i >= salt["max"].to_i - 1 && salt["max"].to_i >= 4 }
      return [] if hot.empty?

      [ {
        "kind" => "salt_mismatch",
        "severity" => "notice",
        "message" => "Salt scores spread #{salt['spread']} across the pod. Talk through fast mana, mass land denial, extra turns, or stax before turn one.",
        "decks" => hot.map { |s| deck_ref(s) }
      } ]
    end

    def friction_mismatch_warning(slots, aggregates)
      friction = aggregates["social_friction"]
      return [] unless friction && friction["max"].to_i >= 4

      hot = slots.select { |s| s.dig("scores", "social_friction").to_i >= 4 }
      [ {
        "kind" => "friction_disclosure",
        "severity" => "notice",
        "message" => "At least one deck wants Rule 0 disclosure (combo lines, long lock games, asymmetric interaction).",
        "decks" => hot.map { |s| deck_ref(s) }
      } ]
    end

    def combo_density_warning(slots)
      combo_decks = slots.select { |s| s.dig("feature_vector", "role_counts", "combo").to_i >= 3 }
      return [] if combo_decks.empty?

      [ {
        "kind" => "combo_density",
        "severity" => "notice",
        "message" => "Compact combo lines detected. Disclose win conditions before keeping opening hands.",
        "decks" => combo_decks.map { |s| deck_ref(s) }
      } ]
    end

    def deck_ref(slot)
      { "deck_id" => slot["deck_id"], "deck_name" => slot["deck_name"] }
    end
  end
end
