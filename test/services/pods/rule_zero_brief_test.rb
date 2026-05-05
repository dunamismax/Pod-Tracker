require "test_helper"

module Pods
  class RuleZeroBriefTest < ActiveSupport::TestCase
    test "names the band and summarizes spread when decks land within the same band" do
      slots = build_slots([
        { name: "Atraxa", power: 6, speed: 5, interaction: 6, salt: 1, social_friction: 1, combo: 0, stax: 0 },
        { name: "Kinnan", power: 7, speed: 6, interaction: 5, salt: 1, social_friction: 1, combo: 0, stax: 0 },
        { name: "Najeela", power: 7, speed: 6, interaction: 6, salt: 2, social_friction: 1, combo: 1, stax: 0 }
      ])
      aggregates = aggregates_for(slots)

      brief = Pods::RuleZeroBrief.new.call(slots, aggregates, [])

      assert_equal "Mid-power", brief.dig("power_band", "label")
      assert_match(/spread|inside|even pod/i, brief.dig("power_band", "summary"))
      assert brief.dig("speed", "average").positive?
    end

    test "calls out combo and stax pressure" do
      slots = build_slots([
        { name: "Krenko", power: 4, speed: 5, interaction: 3, salt: 0, social_friction: 0, combo: 0, stax: 0 },
        { name: "Najeela", power: 9, speed: 8, interaction: 7, salt: 7, social_friction: 5, combo: 4, stax: 3 }
      ])
      aggregates = aggregates_for(slots)

      brief = Pods::RuleZeroBrief.new.call(slots, aggregates, [])

      notes = brief["combo_stax_notes"]
      assert notes.any? { |n| n.include?("combo pieces") }
      assert notes.any? { |n| n.include?("stax pieces") }
    end

    private

    def build_slots(rows)
      rows.map.with_index do |row, idx|
        {
          "slot_id" => idx + 1,
          "position" => idx + 1,
          "deck_id" => idx + 1,
          "deck_name" => row[:name],
          "commander_names" => [],
          "label" => nil,
          "scores" => {
            "power" => row[:power], "speed" => row[:speed], "interaction" => row[:interaction],
            "consistency" => 5, "salt" => row[:salt], "social_friction" => row[:social_friction],
            "confidence" => 1.0
          },
          "feature_vector" => {
            "role_counts" => { "combo" => row[:combo], "stax" => row[:stax] }
          }
        }
      end
    end

    def aggregates_for(slots)
      Pods::Analyzer::AXES.index_with do |axis|
        values = slots.map { |s| s.dig("scores", axis) }.compact
        next { "average" => nil, "min" => nil, "max" => nil, "spread" => nil, "values" => [], "outliers" => [] } if values.empty?
        avg = (values.sum.to_f / values.size).round(2)
        { "average" => avg, "min" => values.min, "max" => values.max, "spread" => values.max - values.min, "values" => values, "outliers" => [] }
      end
    end
  end
end
