module Decks
  # View-facing helper that flattens the AI deck-evaluation payload into
  # the same shape the deck show partials expect. When a successful AI
  # run is present, the deck page reads from this object instead of the
  # deterministic scorecard so the AI call becomes the authoritative
  # bracket and power-band display.
  class AiEvaluationPresenter
    AXES = Codex::DeckEvaluationSchema::AXES

    def self.for(analysis_run)
      return nil unless analysis_run&.status == "succeeded"

      payload = analysis_run.ai_payload
      return nil unless payload.is_a?(Hash) && payload["schema_version"] == Codex::DeckEvaluationSchema::VERSION

      new(analysis_run: analysis_run, payload: payload)
    end

    attr_reader :analysis_run, :payload

    def initialize(analysis_run:, payload:)
      @analysis_run = analysis_run
      @payload = payload
    end

    def summary
      payload["summary"]
    end

    def bracket
      payload["bracket"] || {}
    end

    def bracket_value
      bracket["value"]
    end

    def bracket_label
      bracket["label"]
    end

    def bracket_sub_band
      bracket["sub_band"]
    end

    def bracket_headline
      bracket["headline"]
    end

    def bracket_tagline
      bracket["tagline"]
    end

    def expected_min_turn
      bracket["expected_min_turn"]
    end

    def restrictions
      Array(bracket["restrictions"])
    end

    def game_changers
      Array(bracket["game_changers"])
    end

    def bracket_evidence
      Array(bracket["evidence"])
    end

    def bracket_uncertainty
      Array(bracket["uncertainty"])
    end

    def axes
      payload["axes"] || {}
    end

    def axis(key)
      axes[key.to_s] || {}
    end

    def axis_value(key)
      v = axis(key)["value"]
      v.is_a?(Integer) ? v : nil
    end

    def friction_drivers
      Array(payload["friction_drivers"])
    end

    def talking_points
      Array(payload["rule_zero_talking_points"])
    end

    def recommendations
      Array(payload["recommendations"]).map do |item|
        {
          "title" => item["title"],
          "detail" => item["detail"],
          "category" => item["category"],
          "owned_collection_relevance" => item["owned_collection_relevance"]
        }
      end
    end

    def legality_review
      payload["legality_review"]
    end

    def model
      analysis_run.ai_model
    end

    def prompt_version
      analysis_run.prompt_version
    end

    def completed_at
      analysis_run.completed_at
    end

    def latency_ms
      analysis_run.latency_ms
    end

    def stale?
      analysis_run.stale?
    end
  end
end
