module Codex
  # Validates deck-evaluation-v2 responses. The AI is authoritative for
  # bracket placement and the six axes when this validator passes.
  class DeckEvaluationValidator
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
      bracket
      axes
    ].freeze

    OPTIONAL_ROOT_KEYS = %w[friction_drivers rule_zero_talking_points recommendations legality_review].freeze

    BRACKET_KEYS = %w[value label sub_band headline tagline restrictions evidence uncertainty].freeze
    BRACKET_OPTIONAL_KEYS = %w[expected_min_turn game_changers].freeze
    AXIS_KEYS = %w[value rationale evidence uncertainty].freeze
    DRIVER_KEYS = %w[label severity explanation].freeze
    DRIVER_OPTIONAL_KEYS = %w[evidence].freeze
    TALKING_KEYS = %w[topic prompt].freeze
    RECOMMENDATION_KEYS = %w[category title detail].freeze
    RECOMMENDATION_OPTIONAL_KEYS = %w[owned_collection_relevance].freeze
    RESTRICTION_KEYS = %w[label status detail].freeze
    RESTRICTION_OPTIONAL_KEYS = %w[evidence].freeze
    GAME_CHANGER_KEYS = %w[name].freeze
    GAME_CHANGER_OPTIONAL_KEYS = %w[category].freeze

    def validate(response)
      payload = parse(response)

      unless payload.is_a?(Hash)
        return Result.new(payload: payload, errors: [ "response must be a JSON object" ])
      end

      payload = DeckEvaluationNormalizer.new.call(payload)
      errors = []

      validate_keys(payload, ROOT_KEYS, OPTIONAL_ROOT_KEYS, "$", errors)
      validate_schema_version(payload, errors)
      validate_present_string(payload, "summary", "$.summary", errors)
      validate_bracket(payload["bracket"], errors)
      validate_axes(payload["axes"], errors)
      if payload.key?("friction_drivers")
        validate_array(payload["friction_drivers"], "$.friction_drivers", errors, max: 12) do |item, path|
          validate_keys(item, DRIVER_KEYS, DRIVER_OPTIONAL_KEYS, path, errors)
          validate_present_string(item, "label", "#{path}.label", errors)
          validate_enum(item, "severity", DeckEvaluationSchema::SEVERITIES, "#{path}.severity", errors)
          validate_present_string(item, "explanation", "#{path}.explanation", errors)
          validate_optional_string_array(item["evidence"], "#{path}.evidence", errors)
        end
      end
      if payload.key?("rule_zero_talking_points")
        validate_array(payload["rule_zero_talking_points"], "$.rule_zero_talking_points", errors, max: 12) do |item, path|
          validate_keys(item, TALKING_KEYS, [], path, errors)
          validate_present_string(item, "topic", "#{path}.topic", errors)
          validate_present_string(item, "prompt", "#{path}.prompt", errors)
        end
      end
      if payload.key?("recommendations")
        validate_array(payload["recommendations"], "$.recommendations", errors, max: 12) do |item, path|
          validate_keys(item, RECOMMENDATION_KEYS, RECOMMENDATION_OPTIONAL_KEYS, path, errors)
          validate_present_string(item, "category", "#{path}.category", errors)
          validate_present_string(item, "title", "#{path}.title", errors)
          validate_present_string(item, "detail", "#{path}.detail", errors)
          if item.key?("owned_collection_relevance")
            validate_enum(item, "owned_collection_relevance", DeckEvaluationSchema::OWNERSHIP_RELEVANCE, "#{path}.owned_collection_relevance", errors)
          end
        end
      end

      if payload.key?("legality_review")
        validate_legality_review(payload["legality_review"], errors)
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
      return if payload["schema_version"] == DeckEvaluationSchema::VERSION

      errors << "$.schema_version must be #{DeckEvaluationSchema::VERSION}"
    end

    def validate_bracket(bracket, errors)
      unless bracket.is_a?(Hash)
        errors << "$.bracket must be an object"
        return
      end

      validate_keys(bracket, BRACKET_KEYS, BRACKET_OPTIONAL_KEYS, "$.bracket", errors)
      unless DeckEvaluationSchema::BRACKETS.include?(bracket["value"])
        errors << "$.bracket.value must be one of #{DeckEvaluationSchema::BRACKETS.join(', ')}"
      end
      validate_present_string(bracket, "label", "$.bracket.label", errors)
      validate_enum(bracket, "sub_band", DeckEvaluationSchema::SUB_BANDS, "$.bracket.sub_band", errors)
      validate_present_string(bracket, "headline", "$.bracket.headline", errors)
      validate_present_string(bracket, "tagline", "$.bracket.tagline", errors)

      if bracket.key?("expected_min_turn") && !bracket["expected_min_turn"].nil?
        v = bracket["expected_min_turn"]
        unless v.is_a?(Integer) && v.between?(1, 30)
          errors << "$.bracket.expected_min_turn must be null or an integer between 1 and 30"
        end
      end

      validate_array(bracket["restrictions"], "$.bracket.restrictions", errors, max: 12) do |item, path|
        validate_keys(item, RESTRICTION_KEYS, RESTRICTION_OPTIONAL_KEYS, path, errors)
        validate_present_string(item, "label", "#{path}.label", errors)
        validate_enum(item, "status", DeckEvaluationSchema::RESTRICTION_STATUSES, "#{path}.status", errors)
        validate_present_string(item, "detail", "#{path}.detail", errors)
        validate_optional_string_array(item["evidence"], "#{path}.evidence", errors)
      end

      if bracket.key?("game_changers")
        validate_array(bracket["game_changers"], "$.bracket.game_changers", errors, max: 80) do |item, path|
          validate_keys(item, GAME_CHANGER_KEYS, GAME_CHANGER_OPTIONAL_KEYS, path, errors)
          validate_present_string(item, "name", "#{path}.name", errors)
        end
      end

      validate_optional_string_array(bracket["evidence"], "$.bracket.evidence", errors, max: 24)
      validate_optional_string_array(bracket["uncertainty"], "$.bracket.uncertainty", errors)
    end

    def validate_axes(axes, errors)
      unless axes.is_a?(Hash)
        errors << "$.axes must be an object"
        return
      end

      validate_keys(axes, DeckEvaluationSchema::AXES, [], "$.axes", errors)
      DeckEvaluationSchema::AXES.each do |axis|
        item = axes[axis]
        path = "$.axes.#{axis}"
        unless item.is_a?(Hash)
          errors << "#{path} must be an object"
          next
        end

        validate_keys(item, AXIS_KEYS, [], path, errors)
        validate_integer_range(item, "value", 0, 10, "#{path}.value", errors)
        validate_present_string(item, "rationale", "#{path}.rationale", errors)
        validate_optional_string_array(item["evidence"], "#{path}.evidence", errors, max: 24)
        validate_optional_string_array(item["uncertainty"], "#{path}.uncertainty", errors)
      end
    end

    def validate_legality_review(review, errors)
      unless review.is_a?(Hash)
        errors << "$.legality_review must be an object"
        return
      end

      validate_keys(review, %w[note], %w[flagged_cards], "$.legality_review", errors)
      validate_present_string(review, "note", "$.legality_review.note", errors)
      if review.key?("flagged_cards")
        validate_optional_string_array(review["flagged_cards"], "$.legality_review.flagged_cards", errors, max: 24)
      end
    end

    def validate_array(value, path, errors, min: 0, max:, &block)
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
      end
    end

    def validate_optional_string_array(value, path, errors, max: 64)
      return if value.nil?
      unless value.is_a?(Array)
        errors << "#{path} must be an array of strings"
        return
      end
      errors << "#{path} must have at most #{max} item(s)" if value.size > max
      value.each_with_index do |item, idx|
        unless item.is_a?(String) && item.present?
          errors << "#{path}[#{idx}] must be a non-empty string"
        end
      end
    end

    def validate_keys(object, required, optional, path, errors)
      missing = required - object.keys
      extra = object.keys - required - optional
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
  end
end
