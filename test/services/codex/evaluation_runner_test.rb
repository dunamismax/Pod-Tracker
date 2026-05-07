require "test_helper"

module Codex
  class EvaluationRunnerTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @user = users(:one)
      @user.codex_account&.destroy
      @user.create_codex_account!(
        auth_mode: AccountConnections::BROWSER_AUTH_MODE,
        status: "connected",
        encrypted_credential_payload: "opaque",
        rate_limit_snapshot: { "primary" => { "used" => 1, "limit" => 100 } },
        connected_at: Time.current
      )
      CommanderFormat::CardTagImporter.new.import!
      LegalitySnapshot.find_or_create_by!(
        source: "mtgcommander",
        format: "commander",
        effective_on: Date.new(2026, 2, 9)
      )
      @deck = Decks::FixtureLibrary.new.build_deck("high_power_najeela_5c", user: @user)
      @deck.save!
      Decks::Analyzer.run(@deck, user: @user)
      clear_enqueued_jobs
    end

    teardown do
      clear_enqueued_jobs
    end

    test "enqueue_deck creates a queued replayable AI run and schedules the job" do
      assert_difference -> { @deck.analysis_runs.where(kind: "ai").count }, 1 do
        assert_enqueued_with(job: CodexEvaluationJob) do
          Codex::EvaluationRunner.enqueue_deck!(@deck, user: @user)
        end
      end

      run = @deck.latest_ai_run
      assert_equal "queued", run.status
      assert_equal Codex::DeckEvaluationPrompt::PROMPT_VERSION, run.prompt_version
      assert_equal Codex::ScorecardResponseSchema::VERSION, run.rubric_version
      assert_equal @deck.name, run.ai_request_snapshot.dig("target", "name")
      assert_equal @user.codex_account.rate_limit_snapshot, run.codex_rate_limit_snapshot
      assert_equal Codex::EvaluationRunner::DEFAULT_MODEL_LABEL, run.ai_model
    end

    test "run stores validated output, latency, prompt metadata, and rate-limit snapshot" do
      run = Codex::EvaluationRunner.enqueue_deck!(@deck, user: @user)
      client = FakeEvaluationClient.new(file_fixture("codex_scorecard_response_v1.json").read)

      Codex::EvaluationRunner.new(client: client, clock: StepClock.new).run!(run)

      run.reload
      assert_equal "succeeded", run.status
      assert_equal Codex::DeckEvaluationPrompt::PROMPT_VERSION, run.prompt_version
      assert_equal "fake-model", run.ai_model
      assert_operator run.latency_ms, :>, 0
      assert_match(/directionally right/, run.ai_response_snapshot.dig("validated_response", "summary"))
      assert_equal @deck.name, run.ai_request_snapshot.dig("target", "name")
      assert_equal @user.codex_account.rate_limit_snapshot, run.codex_rate_limit_snapshot
    end

    test "invalid model output marks the run failed" do
      run = Codex::EvaluationRunner.enqueue_deck!(@deck, user: @user)
      client = FakeEvaluationClient.new("{\"not\":\"the schema\"}")

      Codex::EvaluationRunner.new(client: client, clock: StepClock.new).run!(run)

      run.reload
      assert_equal "failed", run.status
      assert_equal "invalid_ai_response", run.error_code
    end

    class FakeEvaluationClient
      def initialize(text)
        @text = text
      end

      def evaluate_scorecard(_prompt, model:)
        raise "expected app-server default model" unless model.nil?

        {
          "text" => @text,
          "model" => "fake-model",
          "thread" => { "id" => "thread-test" },
          "turn" => { "id" => "turn-test" },
          "items" => [],
          "notifications" => [ { "method" => "turn/completed" } ]
        }
      end
    end

    class StepClock
      def initialize
        @time = Time.zone.local(2026, 5, 7, 12, 0, 0)
      end

      def call
        @time += 1.second
      end
    end
  end
end
