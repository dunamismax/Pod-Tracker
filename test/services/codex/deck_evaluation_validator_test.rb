require "test_helper"

module Codex
  class DeckEvaluationValidatorTest < ActiveSupport::TestCase
    test "schema exposes the required deck-evaluation contract" do
      schema = DeckEvaluationSchema.to_h

      assert_equal "https://json-schema.org/draft/2020-12/schema", schema["$schema"]
      assert_equal DeckEvaluationSchema::VERSION, schema.dig("properties", "schema_version", "const")
      assert_includes schema["required"], "bracket"
      assert_includes schema["required"], "axes"
      assert_equal DeckEvaluationSchema::AXES, schema.dig("properties", "axes", "required")
    end

    test "accepts the recorded v2 deck-evaluation fixture" do
      payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)

      result = DeckEvaluationValidator.new.validate(payload)

      assert result.valid?, result.errors.join("\n")
      assert_equal DeckEvaluationSchema::VERSION, result.payload["schema_version"]
      assert_equal 4, result.payload.dig("bracket", "value")
      assert_equal "high", result.payload.dig("bracket", "sub_band")
    end

    test "rejects out-of-range axis values" do
      payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
      payload["axes"]["power"]["value"] = 11

      result = DeckEvaluationValidator.new.validate(payload)

      assert_not result.valid?
      assert_includes result.errors, "$.axes.power.value must be an integer between 0 and 10"
    end

    test "rejects bracket values outside 1..5" do
      payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
      payload["bracket"]["value"] = 6

      result = DeckEvaluationValidator.new.validate(payload)

      assert_not result.valid?
      assert_includes result.errors, "$.bracket.value must be one of 1, 2, 3, 4, 5"
    end

    test "rejects unknown root keys that the normalizer can't salvage" do
      payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
      payload["totally_unrelated"] = { "x" => 1 }

      result = DeckEvaluationValidator.new.validate(payload)

      assert_not result.valid?
      assert_includes result.errors, "$.totally_unrelated is not allowed"
    end

    test "synthesizes a summary when the AI omits it but provides bracket headline/tagline" do
      payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
      payload.delete("summary")

      result = DeckEvaluationValidator.new.validate(payload)

      assert result.valid?, result.errors.join("\n")
      assert result.payload["summary"].present?
    end

    test "coerces unknown restriction status into a safe value" do
      payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
      payload["bracket"]["restrictions"][0]["status"] = "weirdo"

      result = DeckEvaluationValidator.new.validate(payload)

      assert result.valid?, result.errors.join("\n")
      assert_includes DeckEvaluationSchema::RESTRICTION_STATUSES, result.payload.dig("bracket", "restrictions", 0, "status")
    end
  end
end
