module Codex
  class ScorecardResponseSchema
    VERSION = "ai-scorecard-v1".freeze
    AXES = %w[power speed interaction consistency salt social_friction].freeze
    SEVERITIES = %w[low moderate high].freeze
    OWNERSHIP_RELEVANCE = %w[unknown owned missing not_applicable].freeze

    def self.to_h
      {
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "$id" => "https://pod-tracker.app/schemas/#{VERSION}.json",
        "title" => "Pod Tracker Codex scorecard response",
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[
          schema_version
          summary
          adjustments
          friction_drivers
          rule_zero_talking_points
          recommendations
        ],
        "properties" => {
          "schema_version" => { "const" => VERSION },
          "summary" => { "type" => "string", "minLength" => 1, "maxLength" => 800 },
          "adjustments" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => AXES,
            "properties" => AXES.index_with { adjustment_schema }
          },
          "friction_drivers" => {
            "type" => "array",
            "maxItems" => 8,
            "items" => friction_driver_schema
          },
          "rule_zero_talking_points" => {
            "type" => "array",
            "minItems" => 1,
            "maxItems" => 8,
            "items" => rule_zero_point_schema
          },
          "recommendations" => {
            "type" => "array",
            "maxItems" => 8,
            "items" => recommendation_schema
          }
        }
      }.deep_dup
    end

    def self.adjustment_schema
      sourced_object_schema(
        required: %w[delta confidence rationale deterministic_fact_refs uncertainty],
        properties: {
          "delta" => { "type" => "integer", "minimum" => -2, "maximum" => 2 },
          "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 },
          "rationale" => { "type" => "string", "minLength" => 1, "maxLength" => 500 }
        }
      )
    end
    private_class_method :adjustment_schema

    def self.friction_driver_schema
      sourced_object_schema(
        required: %w[label severity explanation deterministic_fact_refs uncertainty],
        properties: {
          "label" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "severity" => { "type" => "string", "enum" => SEVERITIES },
          "explanation" => { "type" => "string", "minLength" => 1, "maxLength" => 500 }
        }
      )
    end
    private_class_method :friction_driver_schema

    def self.rule_zero_point_schema
      sourced_object_schema(
        required: %w[topic prompt deterministic_fact_refs uncertainty],
        properties: {
          "topic" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "prompt" => { "type" => "string", "minLength" => 1, "maxLength" => 500 }
        }
      )
    end
    private_class_method :rule_zero_point_schema

    def self.recommendation_schema
      sourced_object_schema(
        required: %w[category title detail owned_collection_relevance deterministic_fact_refs uncertainty],
        properties: {
          "category" => { "type" => "string", "minLength" => 1, "maxLength" => 80 },
          "title" => { "type" => "string", "minLength" => 1, "maxLength" => 120 },
          "detail" => { "type" => "string", "minLength" => 1, "maxLength" => 500 },
          "owned_collection_relevance" => { "type" => "string", "enum" => OWNERSHIP_RELEVANCE }
        }
      )
    end
    private_class_method :recommendation_schema

    def self.sourced_object_schema(required:, properties:)
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => required,
        "properties" => properties.merge(source_properties)
      }
    end
    private_class_method :sourced_object_schema

    def self.source_properties
      {
        "deterministic_fact_refs" => {
          "type" => "array",
          "minItems" => 1,
          "items" => { "type" => "string", "pattern" => "\\Afact\\.[a-z0-9_.-]+\\z" }
        },
        "uncertainty" => {
          "type" => "array",
          "items" => { "type" => "string", "minLength" => 1, "maxLength" => 240 }
        }
      }
    end
    private_class_method :source_properties
  end
end
