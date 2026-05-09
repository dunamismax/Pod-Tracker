module Codex
  class PodEvaluationSchema
    VERSION = "pod-evaluation-v2".freeze
    BRACKETS = (1..5).to_a.freeze
    SUB_BANDS = %w[low mid high].freeze
    AXES = %w[power speed interaction consistency salt social_friction].freeze
    SEVERITIES = %w[low moderate high].freeze
    OWNERSHIP_RELEVANCE = %w[unknown owned missing not_applicable].freeze

    def self.to_h
      {
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "$id" => "https://pod-tracker.app/schemas/#{VERSION}.json",
        "title" => "Pod Tracker Codex pod evaluation",
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[schema_version summary bracket_spread rule_zero_brief axes decks],
        "properties" => {
          "schema_version" => { "const" => VERSION },
          "summary" => { "type" => "string", "minLength" => 1, "maxLength" => 1200 },
          "bracket_spread" => bracket_spread_schema,
          "rule_zero_brief" => rule_zero_brief_schema,
          "axes" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => AXES,
            "properties" => AXES.index_with { axis_schema }
          },
          "decks" => array_schema(deck_schema, min: 2, max: 4),
          "friction_drivers" => array_schema(driver_schema, max: 12),
          "recommendations" => array_schema(recommendation_schema, max: 12)
        }
      }.deep_dup
    end

    def self.bracket_spread_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[min max spread distinct headline verdict rationale evidence uncertainty],
        "properties" => {
          "min" => nullable_bracket_schema,
          "max" => nullable_bracket_schema,
          "spread" => { "type" => %w[integer null], "minimum" => 0, "maximum" => 4 },
          "distinct" => { "type" => "array", "items" => { "type" => "integer", "enum" => BRACKETS } },
          "game_changer_total" => { "type" => %w[integer null], "minimum" => 0 },
          "headline" => { "type" => "string", "minLength" => 1, "maxLength" => 240 },
          "verdict" => { "type" => "string", "minLength" => 1, "maxLength" => 240 },
          "rationale" => { "type" => "string", "minLength" => 1, "maxLength" => 800 },
          "evidence" => string_array_schema(max: 24),
          "uncertainty" => string_array_schema
        }
      }
    end
    private_class_method :bracket_spread_schema

    def self.rule_zero_brief_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[headline pregame_template talking_points disclosures uncertainty],
        "properties" => {
          "headline" => { "type" => "string", "minLength" => 1, "maxLength" => 240 },
          "pregame_template" => { "type" => "string", "minLength" => 1, "maxLength" => 2000 },
          "talking_points" => array_schema(talking_point_schema, max: 12),
          "disclosures" => array_schema(disclosure_schema, max: 12),
          "uncertainty" => string_array_schema
        }
      }
    end
    private_class_method :rule_zero_brief_schema

    def self.axis_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[value rationale evidence uncertainty],
        "properties" => {
          "value" => { "type" => "integer", "minimum" => 0, "maximum" => 10 },
          "rationale" => { "type" => "string", "minLength" => 1, "maxLength" => 700 },
          "evidence" => string_array_schema(max: 24),
          "uncertainty" => string_array_schema
        }
      }
    end
    private_class_method :axis_schema

    def self.deck_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[position deck_name commanders bracket sub_band table_role rationale evidence uncertainty],
        "properties" => {
          "position" => { "type" => "integer", "minimum" => 1, "maximum" => 4 },
          "deck_name" => { "type" => "string", "minLength" => 1, "maxLength" => 160 },
          "commanders" => string_array_schema(max: 4),
          "bracket" => { "type" => "integer", "enum" => BRACKETS },
          "sub_band" => { "type" => "string", "enum" => SUB_BANDS },
          "table_role" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "rationale" => { "type" => "string", "minLength" => 1, "maxLength" => 700 },
          "evidence" => string_array_schema(max: 24),
          "uncertainty" => string_array_schema
        }
      }
    end
    private_class_method :deck_schema

    def self.driver_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[label severity explanation],
        "properties" => {
          "label" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "severity" => { "type" => "string", "enum" => SEVERITIES },
          "explanation" => { "type" => "string", "minLength" => 1, "maxLength" => 600 },
          "evidence" => string_array_schema(max: 16)
        }
      }
    end
    private_class_method :driver_schema

    def self.talking_point_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[topic prompt],
        "properties" => {
          "topic" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "prompt" => { "type" => "string", "minLength" => 1, "maxLength" => 600 }
        }
      }
    end
    private_class_method :talking_point_schema

    def self.disclosure_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[label severity detail],
        "properties" => {
          "label" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "severity" => { "type" => "string", "enum" => SEVERITIES },
          "detail" => { "type" => "string", "minLength" => 1, "maxLength" => 600 },
          "evidence" => string_array_schema(max: 16)
        }
      }
    end
    private_class_method :disclosure_schema

    def self.recommendation_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[category title detail],
        "properties" => {
          "category" => { "type" => "string", "minLength" => 1, "maxLength" => 80 },
          "title" => { "type" => "string", "minLength" => 1, "maxLength" => 160 },
          "detail" => { "type" => "string", "minLength" => 1, "maxLength" => 600 },
          "owned_collection_relevance" => { "type" => "string", "enum" => OWNERSHIP_RELEVANCE }
        }
      }
    end
    private_class_method :recommendation_schema

    def self.nullable_bracket_schema
      { "type" => %w[integer null], "enum" => BRACKETS + [ nil ] }
    end
    private_class_method :nullable_bracket_schema

    def self.string_array_schema(max: 64)
      { "type" => "array", "maxItems" => max, "items" => { "type" => "string", "minLength" => 1, "maxLength" => 240 } }
    end
    private_class_method :string_array_schema

    def self.array_schema(item_schema, min: 0, max:)
      schema = { "type" => "array", "maxItems" => max, "items" => item_schema }
      schema["minItems"] = min if min.positive?
      schema
    end
    private_class_method :array_schema
  end
end
