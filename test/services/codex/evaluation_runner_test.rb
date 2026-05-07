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
      assert_equal Codex::DeckEvaluationSchema::VERSION, run.rubric_version
      assert_equal @deck.name, run.ai_request_snapshot.dig("target", "name")
      assert_equal @user.codex_account.rate_limit_snapshot, run.codex_rate_limit_snapshot
      assert_equal Codex::EvaluationRunner::DEFAULT_MODEL_LABEL, run.ai_model
    end

    test "run stores validated output, latency, prompt metadata, and rate-limit snapshot" do
      run = Codex::EvaluationRunner.enqueue_deck!(@deck, user: @user)
      client = FakeEvaluationClient.new(file_fixture("codex_deck_evaluation_response_v2.json").read)

      Codex::EvaluationRunner.new(client: client, clock: StepClock.new).run!(run)

      run.reload
      assert_equal "succeeded", run.status
      assert_equal Codex::DeckEvaluationPrompt::PROMPT_VERSION, run.prompt_version
      assert_equal "fake-model", run.ai_model
      assert_operator run.latency_ms, :>, 0
      assert_equal 4, run.ai_response_snapshot.dig("validated_response", "bracket", "value")
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

    test "blank model output reports a rate-limit exhausted message and preserves the raw snapshot" do
      run = Codex::EvaluationRunner.enqueue_deck!(@deck, user: @user)
      rate_limit_notification = {
        "method" => "account/rateLimits/updated",
        "params" => {
          "rateLimits" => {
            "limitId" => "codex",
            "primary" => { "usedPercent" => 100, "windowDurationMins" => 300, "resetsAt" => 1778190775 },
            "secondary" => { "usedPercent" => 54, "windowDurationMins" => 10080 },
            "credits" => { "hasCredits" => false, "balance" => "0", "unlimited" => false },
            "planType" => "plus"
          }
        }
      }
      client = FakeEvaluationClient.new("", notifications: [ rate_limit_notification ])

      Codex::EvaluationRunner.new(client: client, clock: StepClock.new).run!(run)

      run.reload
      assert_equal "failed", run.status
      assert_equal "invalid_ai_response", run.error_code
      assert_match(/codex primary window exhausted/, run.error_message)
      assert_equal "", run.ai_response_snapshot["raw_text"], "raw_text should be persisted even on failure"
      assert_equal 1, run.ai_response_snapshot["notification_count"]
      assert_equal 100, run.ai_response_snapshot.dig("latest_rate_limit_snapshot", "primary", "usedPercent")
    end

    test "enqueue_pod uses the v2 pod prompt and runner validates pod output" do
      pod = build_pod

      assert_difference -> { pod.analysis_runs.where(kind: "ai").count }, 1 do
        assert_enqueued_with(job: CodexEvaluationJob) do
          Codex::EvaluationRunner.enqueue_pod!(pod, user: @user)
        end
      end

      run = pod.latest_ai_run
      assert_equal Codex::PodEvaluationPrompt::PROMPT_VERSION, run.prompt_version
      assert_equal Codex::PodEvaluationSchema::VERSION, run.rubric_version

      client = FakeEvaluationClient.new(file_fixture("codex_pod_evaluation_response_v2.json").read)
      Codex::EvaluationRunner.new(client: client, clock: StepClock.new).run!(run)

      run.reload
      assert_equal "succeeded", run.status
      assert_equal Codex::PodEvaluationSchema::VERSION, run.ai_response_snapshot.dig("validated_response", "schema_version")
      assert_equal "Mixed pod from Core to cEDH", run.ai_response_snapshot.dig("validated_response", "bracket_spread", "headline")
    end

    test "two concurrent runs for two different users get two distinct per-user clients" do
      other = users(:two)
      other.codex_account&.destroy
      other.create_codex_account!(
        auth_mode: Codex::AccountConnections::BROWSER_AUTH_MODE,
        status: "connected",
        encrypted_credential_payload: "opaque",
        connected_at: Time.current
      )
      other_deck = Decks::FixtureLibrary.new.build_deck("high_power_najeela_5c", user: other)
      other_deck.save!
      Decks::Analyzer.run(other_deck, user: other)

      run_a = Codex::EvaluationRunner.enqueue_deck!(@deck, user: @user)
      run_b = Codex::EvaluationRunner.enqueue_deck!(other_deck, user: other)

      built = []
      previous_factory = Codex::EvaluationRunner.client_factory
      response_text = file_fixture("codex_deck_evaluation_response_v2.json").read
      Codex::EvaluationRunner.client_factory = ->(user) {
        client = FakeEvaluationClient.new(response_text)
        built << [ user.id, client.object_id ]
        client
      }

      Codex::EvaluationRunner.new.run!(run_a)
      Codex::EvaluationRunner.new.run!(run_b)

      assert_equal [ @user.id, other.id ], built.map(&:first)
      assert_equal 2, built.map(&:last).uniq.size, "expected each run to construct a fresh client"
    ensure
      Codex::EvaluationRunner.client_factory = previous_factory
    end

    class FakeEvaluationClient
      def initialize(text, notifications: nil)
        @text = text
        @notifications = notifications
      end

      def evaluate_scorecard(_prompt, model:)
        raise "expected app-server default model" unless model.nil?

        {
          "text" => @text,
          "model" => "fake-model",
          "thread" => { "id" => "thread-test" },
          "turn" => { "id" => "turn-test" },
          "items" => [],
          "notifications" => @notifications || [ { "method" => "turn/completed" } ]
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

    def build_pod
      library = Decks::FixtureLibrary.new
      decks = %w[
        precon_korlash_mono_black
        atraxa_superfriends_upgraded
        cedh_tymna_thrasios_thoracle
      ].map do |slug|
        deck = library.build_deck(slug, user: @user)
        deck.save!
        Decks::Analyzer.run(deck, user: @user)
        deck
      end

      Pod.create!(user: @user, name: "Runner pod", format: "commander", status: "draft").tap do |pod|
        decks.each_with_index do |deck, idx|
          pod.pod_slots.create!(deck: deck, position: idx + 1)
        end
        Pods::Analyzer.run(pod, user: @user)
      end
    end
  end
end
