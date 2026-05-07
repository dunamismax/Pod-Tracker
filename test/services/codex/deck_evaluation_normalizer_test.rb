require "test_helper"

module Codex
  class DeckEvaluationNormalizerTest < ActiveSupport::TestCase
    test "salvages the natural LLM shape into a schema-valid payload" do
      raw = {
        "deck_id" => 99,
        "deck_name" => "Najeela 5C",
        "format" => "commander",
        "bracket" => {
          "value" => 5,
          "label" => "cEDH",
          "sub_band" => "high",
          "rationale" => "Tuned cEDH metagame deck with multiple Game Changers and a fast combat win."
        },
        "axes" => {
          "power" => { "value" => 9, "rationale" => "Wins fast with prepared interaction.", "evidence" => [ "Najeela" ] },
          "speed" => { "value" => 9, "rationale" => "Fast mana plus tutors.", "evidence" => [ "Mana Vault" ] },
          "interaction" => { "value" => 8, "rationale" => "Free counters.", "evidence" => [ "Force of Will" ] },
          "consistency" => { "value" => 9, "rationale" => "Tutor suite.", "evidence" => [ "Demonic Tutor" ] },
          "salt" => { "value" => 7, "rationale" => "One-turn kill.", "evidence" => [ "Najeela" ] },
          "social_friction" => { "value" => 8, "rationale" => "Combo timing.", "evidence" => [ "Najeela" ] }
        },
        "game_changers" => [ { "name" => "Mana Vault", "category" => "fast_mana" } ],
        "restrictions" => [
          { "label" => "Game Changers", "status" => "any_allowed", "detail" => "Bracket 5 permits any GC count." }
        ],
        "key_evidence" => [ "Five Game Changers", "Tutored mana base" ],
        "uncertainty" => [ "Pod meta unknown" ],
        "legality_review" => { "legal" => true, "note" => "All cards Commander-legal." }
      }

      payload = DeckEvaluationNormalizer.new.call(raw)
      result = DeckEvaluationValidator.new.validate(payload)

      assert result.valid?, result.errors.join("\n")
      assert_equal "deck-evaluation-v2", payload["schema_version"]
      assert_not payload.key?("deck_id")
      assert_not payload.key?("deck_name")
      assert_not payload.key?("format")
      assert_not payload.key?("game_changers"), "game_changers should be nested under bracket"
      assert_not payload.key?("restrictions")
      assert_not payload.key?("key_evidence")
      assert_not payload.key?("uncertainty")
      assert_not payload.dig("bracket").key?("rationale"), "bracket.rationale must be normalized away"
      assert payload.dig("bracket", "headline").present?
      assert payload.dig("bracket", "tagline").present?
      assert_equal [ "Five Game Changers", "Tutored mana base" ], payload.dig("bracket", "evidence")
      assert_equal [ "Pod meta unknown" ], payload.dig("bracket", "uncertainty")
      assert_equal 1, payload.dig("bracket", "restrictions").length
      assert_equal 1, payload.dig("bracket", "game_changers").length
      assert_equal({ "note" => "All cards Commander-legal." }, payload["legality_review"])

      payload["axes"].each_value do |axis|
        assert_equal [], axis["uncertainty"], "axis uncertainty defaults to empty array"
      end

      assert payload["summary"].present?, "summary synthesized from headline/tagline when missing"
      assert_equal [], payload["friction_drivers"]
      assert_equal [], payload["rule_zero_talking_points"]
      assert_equal [], payload["recommendations"]
    end

    test "leaves a canonical fixture untouched after normalization" do
      raw = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
      normalized = DeckEvaluationNormalizer.new.call(raw.deep_dup)

      assert DeckEvaluationValidator.new.validate(normalized).valid?
      assert_equal raw["bracket"]["value"], normalized["bracket"]["value"]
      assert_equal raw["axes"]["power"]["value"], normalized["axes"]["power"]["value"]
      assert_equal raw["summary"], normalized["summary"]
    end

    test "coerces stringy restrictions and bracket.score axis variants" do
      raw = {
        "schema_version" => "deck-evaluation-v2",
        "summary" => "Test summary.",
        "bracket" => {
          "value" => 3,
          "label" => "Upgraded",
          "sub_band" => "mid",
          "headline" => "Bracket 3",
          "tagline" => "Upgraded mid.",
          "restrictions" => [ "No mass land denial", { "label" => "GC count", "status" => "met", "detail" => "Three GCs" } ],
          "evidence" => [ "ok" ],
          "uncertainty" => []
        },
        "axes" => DeckEvaluationSchema::AXES.index_with do
          { "score" => 5, "rationale" => "fine", "evidence" => [] }
        end
      }

      payload = DeckEvaluationNormalizer.new.call(raw)
      result = DeckEvaluationValidator.new.validate(payload)

      assert result.valid?, result.errors.join("\n")
      assert_equal "ok", payload.dig("bracket", "restrictions", 0, "status")
      assert_equal "ok", payload.dig("bracket", "restrictions", 1, "status")
      payload["axes"].each_value do |axis|
        assert_equal 5, axis["value"]
        assert_not axis.key?("score")
      end
    end
  end
end
