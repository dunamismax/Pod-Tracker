module Codex
  class EvaluationRunner
    DEFAULT_MODEL_LABEL = "app-server-default".freeze

    class Error < StandardError; end
    class QuotaBlocked < Error
      attr_reader :decision

      def initialize(decision)
        @decision = decision
        super(decision.reasons.map { |reason| reason.to_s.humanize.downcase }.to_sentence)
      end
    end
    class MissingTarget < Error; end

    class << self
      attr_writer :client_factory

      def client_factory
        @client_factory ||= -> { AppServerClient.from_environment }
      end

      def enqueue_deck!(deck, user:)
        prompt = DeckEvaluationPrompt.new.call(deck)
        enqueue!(user: user, deck: deck, prompt: prompt)
      end

      def enqueue_pod!(pod, user:)
        prompt = PodEvaluationPrompt.new.call(pod)
        enqueue!(user: user, pod: pod, prompt: prompt)
      end

      def enqueue!(user:, prompt:, deck: nil, pod: nil)
        decision = QuotaPolicy.for(user).check
        raise QuotaBlocked, decision unless decision.allowed?

        run = AnalysisRun.create!(
          user: user,
          deck: deck,
          pod: pod,
          kind: "ai",
          status: "queued",
          rubric_version: prompt.fetch("schema_version"),
          prompt_version: prompt.fetch("prompt_version"),
          ai_model: DEFAULT_MODEL_LABEL,
          queued_at: Time.current,
          codex_rate_limit_snapshot: user.codex_account&.rate_limit_snapshot || {},
          ai_request_snapshot: request_snapshot(prompt, deck: deck, pod: pod)
        )
        CodexEvaluationJob.perform_later(run.id)
        run
      end

      def request_snapshot(prompt, deck:, pod:)
        {
          "target" => {
            "type" => deck ? "deck" : "pod",
            "id" => deck&.id || pod&.id,
            "name" => deck&.name || pod&.name
          },
          "prompt_version" => prompt.fetch("prompt_version"),
          "schema_version" => prompt.fetch("schema_version"),
          "input" => prompt.fetch("input"),
          "messages" => prompt.fetch("messages")
        }
      end
    end

    def initialize(client: self.class.client_factory.call, clock: -> { Time.current })
      @client = client
      @clock = clock
    end

    def run!(analysis_run)
      raise MissingTarget, "AI evaluation run must target a deck or pod" unless analysis_run.deck || analysis_run.pod
      return analysis_run unless analysis_run.status == "queued"

      analysis_run.mark_started!(now: now)
      prompt = prompt_for(analysis_run)
      analysis_run.update!(
        prompt_version: prompt.fetch("prompt_version"),
        rubric_version: prompt.fetch("schema_version"),
        ai_request_snapshot: self.class.request_snapshot(prompt, deck: analysis_run.deck, pod: analysis_run.pod),
        codex_rate_limit_snapshot: analysis_run.user&.codex_account&.rate_limit_snapshot || analysis_run.codex_rate_limit_snapshot
      )

      result = @client.evaluate_scorecard(prompt, model: model_for(analysis_run))
      validated = ScorecardResponseValidator.new.validate!(extract_json_payload(result.fetch("text")))
      analysis_run.update!(
        ai_model: result["model"].presence || analysis_run.ai_model.presence || DEFAULT_MODEL_LABEL,
        ai_response_snapshot: {
          "raw_text" => result.fetch("text"),
          "validated_response" => validated,
          "thread" => result["thread"],
          "turn" => result["turn"],
          "items" => result["items"],
          "notification_count" => Array(result["notifications"]).size
        },
        codex_rate_limit_snapshot: analysis_run.user&.codex_account&.rate_limit_snapshot || analysis_run.codex_rate_limit_snapshot
      )
      analysis_run.mark_succeeded!(now: now, codex_rate_limit_snapshot: analysis_run.codex_rate_limit_snapshot)
      analysis_run
    rescue ScorecardResponseValidator::InvalidResponse => error
      analysis_run.mark_failed!(code: "invalid_ai_response", message: error.message, now: now)
      analysis_run
    rescue AppServerClient::Error => error
      analysis_run.mark_failed!(code: "codex_app_server_error", message: error.message, now: now)
      analysis_run
    rescue StandardError => error
      analysis_run.mark_failed!(code: "ai_evaluation_error", message: error.message, now: now) if analysis_run&.persisted?
      raise
    end

    private

    def now
      @clock.call
    end

    def model_for(run)
      model = run.ai_model.presence
      return nil if model.blank? || model == DEFAULT_MODEL_LABEL

      model
    end

    def prompt_for(run)
      if run.deck
        DeckEvaluationPrompt.new.call(run.deck)
      else
        PodEvaluationPrompt.new.call(run.pod)
      end
    end

    def extract_json_payload(text)
      body = text.to_s.strip
      body = body.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "").strip
      JSON.parse(body)
    rescue JSON::ParserError
      start_idx = body.index("{")
      end_idx = body.rindex("}")
      raise ScorecardResponseValidator::InvalidResponse, [ "response did not contain JSON" ] unless start_idx && end_idx && end_idx >= start_idx

      JSON.parse(body[start_idx..end_idx])
    end
  end
end
