module Codex
  # Reshapes a raw deck-evaluation response into the canonical
  # deck-evaluation-v2 layout before validation. Real LLM runs drift
  # toward a flatter natural shape (bracket fields hoisted to the
  # root, axis uncertainty omitted, an extra `legal` flag in
  # legality_review, prompt-input echoes like deck_id/deck_name); the
  # normalizer salvages those without forcing every prompt rewrite to
  # ship a new schema.
  class DeckEvaluationNormalizer
    AXES = DeckEvaluationSchema::AXES
    BRACKET_LIST_KEYS = %w[restrictions game_changers evidence uncertainty].freeze
    DROP_ROOT_KEYS = %w[deck_id deck_name deck format game_changers restrictions key_evidence evidence uncertainty].freeze

    def call(response)
      return response unless response.is_a?(Hash)

      payload = response.deep_dup
      bracket = payload["bracket"].is_a?(Hash) ? payload["bracket"] : {}

      hoist_bracket_fields(payload, bracket)
      normalize_bracket(bracket)
      payload["bracket"] = bracket

      normalize_axes(payload)
      normalize_optional_arrays(payload)
      normalize_legality_review(payload)
      strip_disallowed_root_keys(payload)
      ensure_summary(payload, bracket)
      payload["schema_version"] ||= DeckEvaluationSchema::VERSION

      payload
    end

    private

    def hoist_bracket_fields(payload, bracket)
      BRACKET_LIST_KEYS.each do |key|
        next if bracket.key?(key) && !bracket[key].nil?

        candidate = payload[key]
        candidate = payload["key_evidence"] if key == "evidence" && candidate.nil?
        bracket[key] = candidate unless candidate.nil?
      end
    end

    def normalize_bracket(bracket)
      rationale = bracket.delete("rationale")
      bracket["headline"] ||= truncate_string(rationale, 240) if rationale.is_a?(String)
      bracket["tagline"] ||= truncate_string(rationale, 240) if rationale.is_a?(String)

      if bracket["headline"].is_a?(String) && bracket["tagline"].blank?
        bracket["tagline"] = bracket["headline"]
      end
      if bracket["tagline"].is_a?(String) && bracket["headline"].blank?
        bracket["headline"] = bracket["tagline"]
      end

      bracket["restrictions"] = normalize_restrictions(bracket["restrictions"])
      bracket["evidence"]     = normalize_string_array(bracket["evidence"])
      bracket["uncertainty"]  = normalize_string_array(bracket["uncertainty"])
      bracket["game_changers"] = normalize_game_changers(bracket["game_changers"]) if bracket.key?("game_changers")

      bracket["expected_min_turn"] = nil unless bracket.key?("expected_min_turn")

      # Strip stray keys that aren't in the schema. Better to drop than to fail.
      allowed = DeckEvaluationValidator::BRACKET_KEYS + DeckEvaluationValidator::BRACKET_OPTIONAL_KEYS
      (bracket.keys - allowed).each { |k| bracket.delete(k) }
    end

    def normalize_restrictions(value)
      return [] if value.nil?
      array = Array(value)
      array.map do |item|
        case item
        when Hash
          {
            "label" => present_string(item["label"]) || "Restriction",
            "status" => coerce_restriction_status(item["status"]),
            "detail" => present_string(item["detail"]) || present_string(item["description"]) || present_string(item["label"]) || "No detail provided.",
            "evidence" => normalize_string_array(item["evidence"])
          }.compact
        when String
          {
            "label" => truncate_string(item, 120) || "Restriction",
            "status" => "ok",
            "detail" => truncate_string(item, 400) || "No detail provided."
          }
        else
          {
            "label" => "Restriction",
            "status" => "ok",
            "detail" => item.to_s.presence || "No detail provided."
          }
        end
      end
    end

    def coerce_restriction_status(status)
      return status if DeckEvaluationSchema::RESTRICTION_STATUSES.include?(status)

      case status.to_s.downcase
      when "met", "pass", "satisfied", "okay" then "ok"
      when "violated", "fail", "fails", "broken" then "violation"
      when "missing", "none" then "absent"
      when "any", "allowed" then "any_allowed"
      when "present" then "present_allowed"
      else
        "ok"
      end
    end

    def normalize_game_changers(value)
      return [] if value.nil?
      Array(value).map do |item|
        case item
        when Hash
          {
            "name" => present_string(item["name"]) || present_string(item["card"]) || "Unknown",
            "category" => present_string(item["category"])
          }.compact
        when String
          { "name" => truncate_string(item, 120) || "Unknown" }
        else
          { "name" => item.to_s.presence || "Unknown" }
        end
      end
    end

    def normalize_axes(payload)
      axes = payload["axes"]
      return unless axes.is_a?(Hash)

      AXES.each do |axis|
        value = axes[axis]
        next unless value.is_a?(Hash)

        value["value"] = value.delete("score") if value["value"].nil? && value.key?("score")
        value["rationale"] = present_string(value["rationale"]) || "Not provided."
        value["evidence"]  = normalize_string_array(value["evidence"])
        value["uncertainty"] = normalize_string_array(value["uncertainty"])

        # Drop stray keys.
        (value.keys - DeckEvaluationValidator::AXIS_KEYS).each { |k| value.delete(k) }
      end

      # Drop axes that aren't in the canonical list to keep validate_keys happy.
      (axes.keys - AXES).each { |k| axes.delete(k) }
    end

    def normalize_optional_arrays(payload)
      payload["friction_drivers"] = normalize_friction_drivers(payload["friction_drivers"])
      payload["rule_zero_talking_points"] = normalize_talking_points(payload["rule_zero_talking_points"])
      payload["recommendations"] = normalize_recommendations(payload["recommendations"])
    end

    def normalize_friction_drivers(value)
      return [] if value.nil?
      Array(value).map do |item|
        next nil unless item.is_a?(Hash)
        severity = item["severity"]
        severity = "moderate" unless DeckEvaluationSchema::SEVERITIES.include?(severity)
        result = {
          "label" => present_string(item["label"]) || "Friction driver",
          "severity" => severity,
          "explanation" => present_string(item["explanation"]) || present_string(item["detail"]) || "No explanation provided."
        }
        result["evidence"] = normalize_string_array(item["evidence"]) if item.key?("evidence")
        result
      end.compact
    end

    def normalize_talking_points(value)
      return [] if value.nil?
      Array(value).map do |item|
        case item
        when Hash
          topic = present_string(item["topic"]) || present_string(item["title"])
          prompt = present_string(item["prompt"]) || present_string(item["text"]) || present_string(item["detail"])
          next nil if topic.blank? && prompt.blank?
          {
            "topic" => topic || prompt.to_s[0, 60],
            "prompt" => prompt || topic
          }
        when String
          { "topic" => truncate_string(item, 60) || "Topic", "prompt" => truncate_string(item, 600) || item }
        end
      end.compact
    end

    def normalize_recommendations(value)
      return [] if value.nil?
      Array(value).map do |item|
        next nil unless item.is_a?(Hash)
        title = present_string(item["title"]) || present_string(item["recommendation"])
        detail = present_string(item["detail"]) || present_string(item["description"])
        next nil if title.blank? && detail.blank?
        result = {
          "category" => present_string(item["category"]) || "general",
          "title" => title || detail.to_s[0, 120],
          "detail" => detail || title
        }
        if item.key?("owned_collection_relevance") && DeckEvaluationSchema::OWNERSHIP_RELEVANCE.include?(item["owned_collection_relevance"])
          result["owned_collection_relevance"] = item["owned_collection_relevance"]
        end
        result
      end.compact
    end

    def normalize_legality_review(payload)
      review = payload["legality_review"]
      return unless review.is_a?(Hash)

      review.delete("legal")
      review.delete("status")
      flagged = review["flagged_cards"]
      review["flagged_cards"] = normalize_string_array(flagged) if flagged
      review.delete("flagged_cards") if review["flagged_cards"].is_a?(Array) && review["flagged_cards"].empty?
      review["note"] = present_string(review["note"]) || "Legality review provided no note."

      # Drop unknown keys.
      (review.keys - %w[note flagged_cards]).each { |k| review.delete(k) }

      payload.delete("legality_review") if review.values.all?(&:nil?)
    end

    def strip_disallowed_root_keys(payload)
      DROP_ROOT_KEYS.each { |k| payload.delete(k) }
    end

    def ensure_summary(payload, bracket)
      summary = present_string(payload["summary"])
      return payload["summary"] = summary if summary

      pieces = [ bracket["headline"], bracket["tagline"] ]
      pieces = pieces.compact.map(&:to_s).reject(&:blank?).uniq
      payload["summary"] = if pieces.any?
        truncate_string(pieces.join(" — "), 1200)
      else
        "Codex deck evaluation completed; no summary supplied."
      end
    end

    def normalize_string_array(value)
      return [] if value.nil?
      Array(value).filter_map do |item|
        next nil if item.nil?
        s = item.to_s.strip
        s.presence
      end
    end

    def present_string(value)
      return nil unless value.is_a?(String)
      stripped = value.strip
      stripped.presence
    end

    def truncate_string(value, max)
      return nil unless value.is_a?(String)
      stripped = value.strip
      return nil if stripped.empty?
      stripped.length > max ? stripped[0, max] : stripped
    end
  end
end
