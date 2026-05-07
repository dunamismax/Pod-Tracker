module Codex
  class ScorecardResponseValidator
    Result = Struct.new(:payload, :errors, keyword_init: true) do
      def valid?
        errors.empty?
      end
    end

    class InvalidResponse < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super(errors.join(", "))
      end
    end

    ROOT_KEYS = %w[
      schema_version
      summary
      adjustments
      friction_drivers
      rule_zero_talking_points
      recommendations
    ].freeze

    ADJUSTMENT_KEYS = %w[delta confidence rationale deterministic_fact_refs uncertainty].freeze
    FRICTION_DRIVER_KEYS = %w[label severity explanation deterministic_fact_refs uncertainty].freeze
    RULE_ZERO_KEYS = %w[topic prompt deterministic_fact_refs uncertainty].freeze
    RECOMMENDATION_KEYS = %w[category title detail owned_collection_relevance deterministic_fact_refs uncertainty].freeze

    FACT_REF_PATTERN = /\Afact\.[a-z0-9_.-]+\z/

    def validate(response)
      payload = parse(response)
      errors = []

      unless payload.is_a?(Hash)
        return Result.new(payload: payload, errors: [ "response must be a JSON object" ])
      end

      validate_keys(payload, ROOT_KEYS, "$", errors)
      validate_schema_version(payload, errors)
      validate_present_string(payload, "summary", "$.summary", errors)
      validate_adjustments(payload["adjustments"], errors)
      validate_sourced_array(payload["friction_drivers"], "$.friction_drivers", errors, max: 8) do |item, path|
        validate_keys(item, FRICTION_DRIVER_KEYS, path, errors)
        validate_present_string(item, "label", "#{path}.label", errors)
        validate_enum(item, "severity", ScorecardResponseSchema::SEVERITIES, "#{path}.severity", errors)
        validate_present_string(item, "explanation", "#{path}.explanation", errors)
      end
      validate_sourced_array(payload["rule_zero_talking_points"], "$.rule_zero_talking_points", errors, min: 1, max: 8) do |item, path|
        validate_keys(item, RULE_ZERO_KEYS, path, errors)
        validate_present_string(item, "topic", "#{path}.topic", errors)
        validate_present_string(item, "prompt", "#{path}.prompt", errors)
      end
      validate_sourced_array(payload["recommendations"], "$.recommendations", errors, max: 8) do |item, path|
        validate_keys(item, RECOMMENDATION_KEYS, path, errors)
        validate_present_string(item, "category", "#{path}.category", errors)
        validate_present_string(item, "title", "#{path}.title", errors)
        validate_present_string(item, "detail", "#{path}.detail", errors)
        validate_enum(item, "owned_collection_relevance", ScorecardResponseSchema::OWNERSHIP_RELEVANCE, "#{path}.owned_collection_relevance", errors)
      end

      Result.new(payload: payload, errors: errors)
    end

    def validate!(response)
      result = validate(response)
      raise InvalidResponse, result.errors unless result.valid?

      result.payload
    end

    private

    def parse(response)
      return response if response.is_a?(Hash)

      JSON.parse(response.to_s)
    rescue JSON::ParserError => e
      { "_parse_error" => e.message }
    end

    def validate_schema_version(payload, errors)
      return if payload["schema_version"] == ScorecardResponseSchema::VERSION

      errors << "$.schema_version must be #{ScorecardResponseSchema::VERSION}"
    end

    def validate_adjustments(adjustments, errors)
      unless adjustments.is_a?(Hash)
        errors << "$.adjustments must be an object"
        return
      end

      validate_keys(adjustments, ScorecardResponseSchema::AXES, "$.adjustments", errors)
      ScorecardResponseSchema::AXES.each do |axis|
        item = adjustments[axis]
        path = "$.adjustments.#{axis}"
        unless item.is_a?(Hash)
          errors << "#{path} must be an object"
          next
        end

        validate_keys(item, ADJUSTMENT_KEYS, path, errors)
        validate_integer_range(item, "delta", -2, 2, "#{path}.delta", errors)
        validate_number_range(item, "confidence", 0, 1, "#{path}.confidence", errors)
        validate_present_string(item, "rationale", "#{path}.rationale", errors)
        validate_sources(item, path, errors)
      end
    end

    def validate_sourced_array(value, path, errors, min: 0, max:, &block)
      unless value.is_a?(Array)
        errors << "#{path} must be an array"
        return
      end
      errors << "#{path} must have at least #{min} item(s)" if value.size < min
      errors << "#{path} must have at most #{max} item(s)" if value.size > max

      value.each_with_index do |item, idx|
        item_path = "#{path}[#{idx}]"
        unless item.is_a?(Hash)
          errors << "#{item_path} must be an object"
          next
        end

        block.call(item, item_path)
        validate_sources(item, item_path, errors)
      end
    end

    def validate_sources(item, path, errors)
      refs = item["deterministic_fact_refs"]
      unless refs.is_a?(Array) && refs.any?
        errors << "#{path}.deterministic_fact_refs must cite at least one deterministic fact"
      else
        refs.each_with_index do |ref, idx|
          errors << "#{path}.deterministic_fact_refs[#{idx}] is not a valid fact ref" unless ref.is_a?(String) && ref.match?(FACT_REF_PATTERN)
        end
      end

      uncertainty = item["uncertainty"]
      errors << "#{path}.uncertainty must be an array" unless uncertainty.is_a?(Array)
    end

    def validate_keys(object, allowed, path, errors)
      missing = allowed - object.keys
      extra = object.keys - allowed
      missing.each { |key| errors << "#{path}.#{key} is required" }
      extra.each { |key| errors << "#{path}.#{key} is not allowed" }
    end

    def validate_present_string(object, key, path, errors)
      value = object[key]
      errors << "#{path} must be a non-empty string" unless value.is_a?(String) && value.present?
    end

    def validate_enum(object, key, allowed, path, errors)
      value = object[key]
      errors << "#{path} must be one of #{allowed.join(', ')}" unless allowed.include?(value)
    end

    def validate_integer_range(object, key, min, max, path, errors)
      value = object[key]
      errors << "#{path} must be an integer between #{min} and #{max}" unless value.is_a?(Integer) && value.between?(min, max)
    end

    def validate_number_range(object, key, min, max, path, errors)
      value = object[key]
      errors << "#{path} must be a number between #{min} and #{max}" unless value.is_a?(Numeric) && value.between?(min, max)
    end
  end
end
