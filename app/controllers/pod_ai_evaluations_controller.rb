class PodAiEvaluationsController < ApplicationController
  def create
    pod = current_user.pods.find(params[:pod_id])
    latest = pod.latest_ai_run
    if latest&.active?
      redirect_to pod_path(pod), notice: "AI evaluation is already #{latest.status}."
      return
    end

    Codex::EvaluationRunner.enqueue_pod!(pod, user: current_user)
    redirect_to pod_path(pod), notice: "AI evaluation queued."
  rescue Codex::EvaluationRunner::QuotaBlocked => error
    redirect_to pod_path(pod), alert: "AI evaluation paused: #{error.message}."
  rescue ArgumentError => error
    redirect_to pod_path(pod), alert: error.message
  end

  private

    def current_user
      Current.session.user
    end
end
