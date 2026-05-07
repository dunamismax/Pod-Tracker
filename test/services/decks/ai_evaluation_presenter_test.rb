require "test_helper"

module Decks
  class AiEvaluationPresenterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      CommanderFormat::CardTagImporter.new.import!
      LegalitySnapshot.find_or_create_by!(
        source: "mtgcommander",
        format: "commander",
        effective_on: Date.new(2026, 2, 9)
      )
      @deck = Decks::FixtureLibrary.new.build_deck("high_power_najeela_5c", user: @user)
      @deck.save!
      Decks::Analyzer.run(@deck, user: @user)
    end

    test "returns nil when there is no AI run" do
      assert_nil Decks::AiEvaluationPresenter.for(nil)
    end

    test "returns nil when the AI run is not yet succeeded" do
      run = @deck.analysis_runs.create!(
        kind: "ai",
        status: "queued",
        rubric_version: Codex::DeckEvaluationSchema::VERSION,
        queued_at: Time.current
      )
      assert_nil Decks::AiEvaluationPresenter.for(run)
    end

    test "returns nil when the response uses the legacy v1 schema" do
      run = succeeded_run(payload: { "schema_version" => "ai-scorecard-v1" })
      assert_nil Decks::AiEvaluationPresenter.for(run)
    end

    test "exposes bracket, axes, drivers, talking points, and recommendations from the v2 payload" do
      payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
      run = succeeded_run(payload: payload)

      presenter = Decks::AiEvaluationPresenter.for(run)
      assert_not_nil presenter
      assert_equal 4, presenter.bracket_value
      assert_equal "high", presenter.bracket_sub_band
      assert_equal "Optimized", presenter.bracket_label
      assert_equal 8, presenter.axis_value("power")
      assert presenter.friction_drivers.any?
      assert presenter.talking_points.any?
      assert presenter.recommendations.first["title"].present?
    end

    private

    def succeeded_run(payload:)
      @deck.analysis_runs.create!(
        kind: "ai",
        status: "succeeded",
        rubric_version: Codex::DeckEvaluationSchema::VERSION,
        prompt_version: Codex::DeckEvaluationPrompt::PROMPT_VERSION,
        queued_at: 5.minutes.ago,
        started_at: 4.minutes.ago,
        completed_at: 3.minutes.ago,
        ai_model: "test-model",
        ai_response_snapshot: { "validated_response" => payload }
      )
    end
  end
end
