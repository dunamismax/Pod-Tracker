module Pods
  class AiEvaluationPresenter
    AXES = Codex::PodEvaluationSchema::AXES

    def self.for(analysis_run)
      return nil unless analysis_run&.status == "succeeded"

      payload = analysis_run.ai_payload
      return nil unless payload.is_a?(Hash) && payload["schema_version"] == Codex::PodEvaluationSchema::VERSION

      new(analysis_run: analysis_run, payload: payload)
    end

    attr_reader :analysis_run, :payload

    def initialize(analysis_run:, payload:)
      @analysis_run = analysis_run
      @payload = payload
    end

    def summary = payload["summary"]

    def bracket_spread = payload["bracket_spread"] || {}

    def rule_zero_brief = payload["rule_zero_brief"] || {}

    def axes = payload["axes"] || {}

    def axis(key) = axes[key.to_s] || {}

    def decks = Array(payload["decks"])

    def friction_drivers = Array(payload["friction_drivers"])

    def recommendations = Array(payload["recommendations"])

    def model = analysis_run.ai_model

    def prompt_version = analysis_run.prompt_version

    def completed_at = analysis_run.completed_at

    def stale? = analysis_run.stale?
  end
end
