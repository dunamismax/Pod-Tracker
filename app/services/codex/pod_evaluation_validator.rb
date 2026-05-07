module Codex
  class PodEvaluationValidator
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

    ROOT_KEYS = %w[schema_version summary bracket_spread rule_zero_brief axes decks].freeze
    OPTIONAL_ROOT_KEYS = %w[friction_drivers recommendations].freeze
    BRACKET_SPREAD_KEYS = %w[min max spread distinct headline verdict rationale evidence uncertainty].freeze
    BRACKET_SPREAD_OPTIONAL_KEYS = %w[game_changer_total].freeze
    RULE_ZERO_KEYS = %w[headline pregame_template talking_points disclosures uncertainty].freeze
    AXIS_KEYS = %w[value rationale evidence uncertainty].freeze
    DECK_KEYS = %w[position deck_name commanders bracket sub_band table_role rationale evidence uncertainty].freeze
    DRIVER_KEYS = %w[label severity explanation].freeze
    DRIVER_OPTIONAL_KEYS = %w[evidence].freeze
    TALKING_POINT_KEYS = %w[topic prompt].freeze
    DISCLOSURE_KEYS = %w[label severity detail].freeze
    DISCLOSURE_OPTIONAL_KEYS = %w[evidence].freeze
    RECOMMENDATION_KEYS = %w[category title detail].freeze
    RECOMMENDATION_OPTIONAL_KEYS = %w[owned_collection_relevance].freeze

    def validate(response)
      payload = parse(response)
      return Result.new(payload: payload, errors: [ "response must be a JSON object" ]) unless payload.is_a?(Hash)

      errors = []
      normalize_optional_arrays(payload)
      validate_keys(payload, ROOT_KEYS, OPTIONAL_ROOT_KEYS, "$", errors)
      validate_schema_version(payload, errors)
      validate_present_string(payload, "summary", "$.summary", errors)
      validate_bracket_spread(payload["bracket_spread"], errors)
      validate_rule_zero_brief(payload["rule_zero_brief"], errors)
      validate_axes(payload["axes"], errors)
      validate_decks(payload["decks"], errors)
      validate_optional_payload_arrays(payload, errors)

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

    def normalize_optional_arrays(payload)
      payload["friction_drivers"] ||= []
      payload["recommendations"] ||= []
    end

    def validate_schema_version(payload, errors)
      return if payload["schema_version"] == PodEvaluationSchema::VERSION

      errors << "$.schema_version must be #{PodEvaluationSchema::VERSION}"
    end

    def validate_bracket_spread(value, errors)
      unless value.is_a?(Hash)
        errors << "$.bracket_spread must be an object"
        return
      end

      validate_keys(value, BRACKET_SPREAD_KEYS, BRACKET_SPREAD_OPTIONAL_KEYS, "$.bracket_spread", errors)
      validate_nullable_bracket(value["min"], "$.bracket_spread.min", errors)
      validate_nullable_bracket(value["max"], "$.bracket_spread.max", errors)
      validate_nullable_integer(value["spread"], 0, 4, "$.bracket_spread.spread", errors)
      validate_integer_array(value["distinct"], PodEvaluationSchema::BRACKETS, "$.bracket_spread.distinct", errors, max: 5)
      validate_nullable_integer(value["game_changer_total"], 0, 200, "$.bracket_spread.game_changer_total", errors) if value.key?("game_changer_total")
      validate_present_string(value, "headline", "$.bracket_spread.headline", errors)
      validate_present_string(value, "verdict", "$.bracket_spread.verdict", errors)
      validate_present_string(value, "rationale", "$.bracket_spread.rationale", errors)
      validate_string_array(value["evidence"], "$.bracket_spread.evidence", errors, max: 24)
      validate_string_array(value["uncertainty"], "$.bracket_spread.uncertainty", errors)
    end

    def validate_rule_zero_brief(value, errors)
      unless value.is_a?(Hash)
        errors << "$.rule_zero_brief must be an object"
        return
      end

      validate_keys(value, RULE_ZERO_KEYS, [], "$.rule_zero_brief", errors)
      validate_present_string(value, "headline", "$.rule_zero_brief.headline", errors)
      validate_present_string(value, "pregame_template", "$.rule_zero_brief.pregame_template", errors)
      validate_array(value["talking_points"], "$.rule_zero_brief.talking_points", errors, max: 12) do |item, path|
        validate_keys(item, TALKING_POINT_KEYS, [], path, errors)
        validate_present_string(item, "topic", "#{path}.topic", errors)
        validate_present_string(item, "prompt", "#{path}.prompt", errors)
      end
      validate_array(value["disclosures"], "$.rule_zero_brief.disclosures", errors, max: 12) do |item, path|
        validate_keys(item, DISCLOSURE_KEYS, DISCLOSURE_OPTIONAL_KEYS, path, errors)
        validate_present_string(item, "label", "#{path}.label", errors)
        validate_enum(item, "severity", PodEvaluationSchema::SEVERITIES, "#{path}.severity", errors)
        validate_present_string(item, "detail", "#{path}.detail", errors)
        validate_string_array(item["evidence"], "#{path}.evidence", errors, max: 16) if item.key?("evidence")
      end
      validate_string_array(value["uncertainty"], "$.rule_zero_brief.uncertainty", errors)
    end

    def validate_axes(axes, errors)
      unless axes.is_a?(Hash)
        errors << "$.axes must be an object"
        return
      end

      validate_keys(axes, PodEvaluationSchema::AXES, [], "$.axes", errors)
      PodEvaluationSchema::AXES.each do |axis|
        item = axes[axis]
        path = "$.axes.#{axis}"
        unless item.is_a?(Hash)
          errors << "#{path} must be an object"
          next
        end

        validate_keys(item, AXIS_KEYS, [], path, errors)
        validate_integer(item["value"], 0, 10, "#{path}.value", errors)
        validate_present_string(item, "rationale", "#{path}.rationale", errors)
        validate_string_array(item["evidence"], "#{path}.evidence", errors, max: 24)
        validate_string_array(item["uncertainty"], "#{path}.uncertainty", errors)
      end
    end

    def validate_decks(decks, errors)
      validate_array(decks, "$.decks", errors, min: 2, max: 4) do |item, path|
        validate_keys(item, DECK_KEYS, [], path, errors)
        validate_integer(item["position"], 1, 4, "#{path}.position", errors)
        validate_present_string(item, "deck_name", "#{path}.deck_name", errors)
        validate_string_array(item["commanders"], "#{path}.commanders", errors, max: 4)
        validate_integer(item["bracket"], 1, 5, "#{path}.bracket", errors)
        validate_enum(item, "sub_band", PodEvaluationSchema::SUB_BANDS, "#{path}.sub_band", errors)
        validate_present_string(item, "table_role", "#{path}.table_role", errors)
        validate_present_string(item, "rationale", "#{path}.rationale", errors)
        validate_string_array(item["evidence"], "#{path}.evidence", errors, max: 24)
        validate_string_array(item["uncertainty"], "#{path}.uncertainty", errors)
      end
    end

    def validate_optional_payload_arrays(payload, errors)
      validate_array(payload["friction_drivers"], "$.friction_drivers", errors, max: 12) do |item, path|
        validate_keys(item, DRIVER_KEYS, DRIVER_OPTIONAL_KEYS, path, errors)
        validate_present_string(item, "label", "#{path}.label", errors)
        validate_enum(item, "severity", PodEvaluationSchema::SEVERITIES, "#{path}.severity", errors)
        validate_present_string(item, "explanation", "#{path}.explanation", errors)
        validate_string_array(item["evidence"], "#{path}.evidence", errors, max: 16) if item.key?("evidence")
      end

      validate_array(payload["recommendations"], "$.recommendations", errors, max: 12) do |item, path|
        validate_keys(item, RECOMMENDATION_KEYS, RECOMMENDATION_OPTIONAL_KEYS, path, errors)
        validate_present_string(item, "category", "#{path}.category", errors)
        validate_present_string(item, "title", "#{path}.title", errors)
        validate_present_string(item, "detail", "#{path}.detail", errors)
        if item.key?("owned_collection_relevance")
          validate_enum(item, "owned_collection_relevance", PodEvaluationSchema::OWNERSHIP_RELEVANCE, "#{path}.owned_collection_relevance", errors)
        end
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

    def validate_string_array(value, path, errors, max: 64)
      unless value.is_a?(Array)
        errors << "#{path} must be an array of strings"
        return
      end
      errors << "#{path} must have at most #{max} item(s)" if value.size > max
      value.each_with_index do |item, idx|
        errors << "#{path}[#{idx}] must be a non-empty string" unless item.is_a?(String) && item.present?
      end
    end

    def validate_integer_array(value, allowed, path, errors, max:)
      unless value.is_a?(Array)
        errors << "#{path} must be an array"
        return
      end
      errors << "#{path} must have at most #{max} item(s)" if value.size > max
      value.each_with_index do |item, idx|
        errors << "#{path}[#{idx}] must be one of #{allowed.join(', ')}" unless allowed.include?(item)
      end
    end

    def validate_nullable_bracket(value, path, errors)
      return if value.nil? || PodEvaluationSchema::BRACKETS.include?(value)

      errors << "#{path} must be null or one of #{PodEvaluationSchema::BRACKETS.join(', ')}"
    end

    def validate_nullable_integer(value, min, max, path, errors)
      return if value.nil?

      validate_integer(value, min, max, path, errors)
    end

    def validate_integer(value, min, max, path, errors)
      errors << "#{path} must be an integer between #{min} and #{max}" unless value.is_a?(Integer) && value.between?(min, max)
    end

    def validate_enum(object, key, allowed, path, errors)
      value = object[key]
      errors << "#{path} must be one of #{allowed.join(', ')}" unless allowed.include?(value)
    end
  end
end
