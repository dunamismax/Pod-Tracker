require "test_helper"

module Codex
  class ScorecardResponseValidatorTest < ActiveSupport::TestCase
    test "schema exposes the required scorecard contract" do
      schema = ScorecardResponseSchema.to_h

      assert_equal "https://json-schema.org/draft/2020-12/schema", schema["$schema"]
      assert_equal ScorecardResponseSchema::VERSION, schema.dig("properties", "schema_version", "const")
      assert_equal ScorecardResponseSchema::AXES, schema.dig("properties", "adjustments", "required")
      assert_equal "array", schema.dig("properties", "rule_zero_talking_points", "type")
    end

    test "accepts the recorded scorecard fixture" do
      payload = JSON.parse(file_fixture("codex_scorecard_response_v1.json").read)

      result = ScorecardResponseValidator.new.validate(payload)

      assert result.valid?, result.errors.join("\n")
      assert_equal ScorecardResponseSchema::VERSION, result.payload["schema_version"]
    end

    test "rejects responses that do not cite deterministic facts" do
      payload = JSON.parse(file_fixture("codex_scorecard_response_v1.json").read)
      payload["adjustments"]["power"]["deterministic_fact_refs"] = []

      result = ScorecardResponseValidator.new.validate(payload)

      assert_not result.valid?
      assert_includes result.errors, "$.adjustments.power.deterministic_fact_refs must cite at least one deterministic fact"
    end

    test "rejects unknown keys and out-of-range adjustments" do
      payload = JSON.parse(file_fixture("codex_scorecard_response_v1.json").read)
      payload["unexpected"] = true
      payload["adjustments"]["speed"]["delta"] = 4

      result = ScorecardResponseValidator.new.validate(payload)

      assert_not result.valid?
      assert_includes result.errors, "$.unexpected is not allowed"
      assert_includes result.errors, "$.adjustments.speed.delta must be an integer between -2 and 2"
    end
  end
end
