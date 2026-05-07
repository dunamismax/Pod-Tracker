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
      # Test override. May accept zero arguments or one (the user that the
      # client should be bound to). Production code does not set this — it
      # falls through to AppServerClient.for(user) so each evaluation spawns
      # a fresh transport against the right user's CODEX_HOME.
      attr_writer :client_factory
      attr_reader :client_factory

      def build_client_for(user)
        if @client_factory
          if @client_factory.respond_to?(:arity) && @client_factory.arity != 0
            @client_factory.call(user)
          else
            @client_factory.call
          end
        else
          AppServerClient.for(user)
        end
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

    def initialize(client: nil, clock: -> { Time.current })
      @client = client
      @clock = clock
    end

    def run!(analysis_run)
      raise MissingTarget, "AI evaluation run must target a deck or pod" unless analysis_run.deck || analysis_run.pod
      return analysis_run unless analysis_run.status == "queued"

      client = @client || self.class.build_client_for(analysis_run.user)
      analysis_run.mark_started!(now: now)
      prompt = prompt_for(analysis_run)
      analysis_run.update!(
        prompt_version: prompt.fetch("prompt_version"),
        rubric_version: prompt.fetch("schema_version"),
        ai_request_snapshot: self.class.request_snapshot(prompt, deck: analysis_run.deck, pod: analysis_run.pod),
        codex_rate_limit_snapshot: analysis_run.user&.codex_account&.rate_limit_snapshot || analysis_run.codex_rate_limit_snapshot
      )

      result = client.evaluate_scorecard(prompt, model: model_for(analysis_run))
      raw_text = result.fetch("text").to_s
      latest_rate_limit = latest_rate_limit_from(result["notifications"])

      # Persist the raw response BEFORE validation so the snapshot survives a
      # parse / validator failure. Without this, an empty or malformed Codex
      # response leaves no forensic trace beyond the failure message.
      analysis_run.update!(
        ai_model: result["model"].presence || analysis_run.ai_model.presence || DEFAULT_MODEL_LABEL,
        ai_response_snapshot: {
          "raw_text" => raw_text,
          "thread" => result["thread"],
          "turn" => result["turn"],
          "items" => result["items"],
          "notification_count" => Array(result["notifications"]).size,
          "latest_rate_limit_snapshot" => latest_rate_limit
        },
        codex_rate_limit_snapshot: analysis_run.user&.codex_account&.rate_limit_snapshot || analysis_run.codex_rate_limit_snapshot
      )

      raise ScorecardResponseValidator::InvalidResponse, [ blank_response_message(latest_rate_limit) ] if raw_text.strip.empty?

      validated = validator_for(analysis_run).validate!(extract_json_payload(raw_text))
      analysis_run.update!(
        ai_response_snapshot: analysis_run.ai_response_snapshot.merge("validated_response" => validated)
      )
      analysis_run.mark_succeeded!(now: now, codex_rate_limit_snapshot: analysis_run.codex_rate_limit_snapshot)
      analysis_run
    rescue ScorecardResponseValidator::InvalidResponse, DeckEvaluationValidator::InvalidResponse, PodEvaluationValidator::InvalidResponse => error
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

    def validator_for(run)
      return DeckEvaluationValidator.new if run.deck
      return PodEvaluationValidator.new if run.pod

      ScorecardResponseValidator.new
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

    # Pull the most recent account/rateLimits/updated notification's rate-limit
    # payload, so the runner can both store it on the run and use it to compose
    # a meaningful failure message when Codex returns an empty response.
    def latest_rate_limit_from(notifications)
      Array(notifications).reverse.each do |message|
        next unless message.is_a?(Hash) && message["method"] == "account/rateLimits/updated"
        snapshot = message.dig("params", "rateLimits") || message.dig("params", "rateLimitsByLimitId")
        return snapshot if snapshot.is_a?(Hash)
      end
      nil
    end

    def blank_response_message(rate_limit)
      reason = rate_limit_exhaustion_reason(rate_limit)
      base = "Codex returned no response. The AI account is unable to answer right now"
      return "#{base}." unless reason
      "#{base} (#{reason}). Try again after the rate-limit window resets, or check the linked ChatGPT account."
    end

    def rate_limit_exhaustion_reason(rate_limit)
      return nil unless rate_limit.is_a?(Hash)
      pools = rate_limit.values.any? { |v| v.is_a?(Hash) && (v.key?("primary") || v.key?(:primary) || v.key?("secondary") || v.key?(:secondary)) } ? rate_limit.values : [ rate_limit ]
      pools.each do |pool|
        next unless pool.is_a?(Hash)
        %w[primary secondary].each do |key|
          window = pool[key] || pool[key.to_sym]
          next unless window.is_a?(Hash)
          used_percent = window["usedPercent"] || window[:usedPercent]
          if used_percent && used_percent.to_f >= 100
            limit_id = pool["limitId"] || pool[:limitId]
            return limit_id ? "#{limit_id} #{key} window exhausted" : "#{key} window exhausted"
          end
        end
        credits = pool["credits"] || pool[:credits]
        if credits.is_a?(Hash)
          has_credits = credits.fetch("hasCredits") { credits[:hasCredits] }
          unlimited = credits.fetch("unlimited") { credits[:unlimited] }
          return "no credits remaining" if has_credits == false && unlimited != true
        end
      end
      nil
    end
  end
end
