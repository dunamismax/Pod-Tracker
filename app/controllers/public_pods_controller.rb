class PublicPodsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    pod = Pod.shared.find_by(share_token: params[:token])
    return render plain: "Not found", status: :not_found unless pod

    @pod = pod
    @latest_run = pod.latest_analysis_run
    @snapshot = @latest_run&.snapshot || {}
    @brief = @latest_run&.rule_zero_brief || {}
    @warnings = Array(@latest_run&.warnings)
    @suggestions = Array(@latest_run&.suggestions)
    @ai_run = pod.latest_ai_run
    @ai_evaluation = Pods::AiEvaluationPresenter.for(@ai_run)
  end
end
