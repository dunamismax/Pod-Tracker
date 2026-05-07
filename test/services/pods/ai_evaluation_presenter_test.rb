require "test_helper"

module Pods
  class AiEvaluationPresenterTest < ActiveSupport::TestCase
    test "returns nil without a successful pod v2 run" do
      assert_nil Pods::AiEvaluationPresenter.for(nil)

      run = AnalysisRun.new(kind: "ai", status: "failed", rubric_version: Codex::PodEvaluationSchema::VERSION)
      assert_nil Pods::AiEvaluationPresenter.for(run)
    end

    test "wraps successful pod v2 payload for views" do
      run = AnalysisRun.new(
        kind: "ai",
        status: "succeeded",
        rubric_version: Codex::PodEvaluationSchema::VERSION,
        prompt_version: Codex::PodEvaluationPrompt::PROMPT_VERSION,
        ai_model: "fake-model",
        completed_at: Time.current,
        ai_response_snapshot: {
          "validated_response" => JSON.parse(file_fixture("codex_pod_evaluation_response_v2.json").read)
        }
      )

      presenter = Pods::AiEvaluationPresenter.for(run)

      assert_equal "Mixed pod from Core to cEDH", presenter.bracket_spread["headline"]
      assert_equal 8, presenter.axis("power")["value"]
      assert_equal 3, presenter.decks.size
      assert_equal "fake-model", presenter.model
    end
  end
end
