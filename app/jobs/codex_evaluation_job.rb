class CodexEvaluationJob < ApplicationJob
  queue_as :default

  def perform(analysis_run_id)
    Codex::EvaluationRunner.new.run!(AnalysisRun.find(analysis_run_id))
  end
end
