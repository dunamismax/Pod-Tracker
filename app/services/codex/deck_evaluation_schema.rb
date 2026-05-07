module Codex
  # JSON schema for the AI deck evaluation response. Unlike the v1
  # adjustment-only contract, v2 makes the AI authoritative for the
  # bracket call and the six 0-10 axes — the deck show page surfaces
  # these values directly when an evaluation succeeds.
  #
  # Legality and card facts remain deterministic; the AI is asked to
  # interpret the supplied decklist against the bracket rules, the
  # canonical Game Changers list, and the Commander banlist that the
  # prompt embeds via Codex::BracketBriefing.
  class DeckEvaluationSchema
    VERSION = "deck-evaluation-v2".freeze
    BRACKETS = (1..5).to_a.freeze
    SUB_BANDS = %w[low mid high].freeze
    AXES = %w[power speed interaction consistency salt social_friction].freeze
    RESTRICTION_STATUSES = %w[ok ok_singleton absent any_allowed present_allowed violation].freeze
    OWNERSHIP_RELEVANCE = %w[unknown owned missing not_applicable].freeze
    SEVERITIES = %w[low moderate high].freeze

    def self.to_h
      {
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "$id" => "https://ideal-magic.com/schemas/#{VERSION}.json",
        "title" => "Ideal Magic Codex deck evaluation",
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[
          schema_version
          summary
          bracket
          axes
          friction_drivers
          rule_zero_talking_points
          recommendations
        ],
        "properties" => {
          "schema_version" => { "const" => VERSION },
          "summary" => { "type" => "string", "minLength" => 1, "maxLength" => 1200 },
          "bracket" => bracket_schema,
          "axes" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => AXES,
            "properties" => AXES.index_with { axis_schema }
          },
          "friction_drivers" => array_schema(driver_schema, max: 12),
          "rule_zero_talking_points" => array_schema(talking_point_schema, min: 1, max: 12),
          "recommendations" => array_schema(recommendation_schema, max: 12),
          "legality_review" => legality_review_schema
        }
      }.deep_dup
    end

    def self.bracket_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[value label sub_band headline tagline restrictions evidence uncertainty],
        "properties" => {
          "value" => { "type" => "integer", "enum" => BRACKETS },
          "label" => { "type" => "string", "minLength" => 1, "maxLength" => 60 },
          "sub_band" => { "type" => "string", "enum" => SUB_BANDS },
          "expected_min_turn" => { "type" => %w[integer null], "minimum" => 1, "maximum" => 30 },
          "headline" => { "type" => "string", "minLength" => 1, "maxLength" => 240 },
          "tagline" => { "type" => "string", "minLength" => 1, "maxLength" => 240 },
          "restrictions" => array_schema(restriction_schema, max: 12),
          "game_changers" => array_schema(game_changer_schema, max: 80),
          "evidence" => { "type" => "array", "maxItems" => 24, "items" => { "type" => "string", "minLength" => 1, "maxLength" => 240 } },
          "uncertainty" => { "type" => "array", "items" => { "type" => "string", "minLength" => 1, "maxLength" => 240 } }
        }
      }
    end
    private_class_method :bracket_schema

    def self.restriction_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[label status detail],
        "properties" => {
          "label" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "status" => { "type" => "string", "enum" => RESTRICTION_STATUSES },
          "detail" => { "type" => "string", "minLength" => 1, "maxLength" => 400 },
          "evidence" => { "type" => "array", "maxItems" => 16, "items" => { "type" => "string", "minLength" => 1, "maxLength" => 120 } }
        }
      }
    end
    private_class_method :restriction_schema

    def self.game_changer_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[name],
        "properties" => {
          "name" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "category" => { "type" => "string", "minLength" => 1, "maxLength" => 60 }
        }
      }
    end
    private_class_method :game_changer_schema

    def self.axis_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[value rationale evidence uncertainty],
        "properties" => {
          "value" => { "type" => "integer", "minimum" => 0, "maximum" => 10 },
          "rationale" => { "type" => "string", "minLength" => 1, "maxLength" => 600 },
          "evidence" => { "type" => "array", "maxItems" => 24, "items" => { "type" => "string", "minLength" => 1, "maxLength" => 240 } },
          "uncertainty" => { "type" => "array", "items" => { "type" => "string", "minLength" => 1, "maxLength" => 240 } }
        }
      }
    end
    private_class_method :axis_schema

    def self.driver_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[label severity explanation],
        "properties" => {
          "label" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "severity" => { "type" => "string", "enum" => SEVERITIES },
          "explanation" => { "type" => "string", "minLength" => 1, "maxLength" => 500 },
          "evidence" => { "type" => "array", "maxItems" => 16, "items" => { "type" => "string", "minLength" => 1, "maxLength" => 240 } }
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

    def self.legality_review_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[note],
        "properties" => {
          "note" => { "type" => "string", "minLength" => 1, "maxLength" => 600 },
          "flagged_cards" => { "type" => "array", "maxItems" => 24, "items" => { "type" => "string", "minLength" => 1, "maxLength" => 120 } }
        }
      }
    end
    private_class_method :legality_review_schema

    def self.array_schema(item_schema, min: 0, max:)
      schema = { "type" => "array", "maxItems" => max, "items" => item_schema }
      schema["minItems"] = min if min.positive?
      schema
    end
    private_class_method :array_schema
  end
end
