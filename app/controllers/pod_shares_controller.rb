class PodSharesController < ApplicationController
  before_action :load_pod

  def create
    @pod.issue_share_token!
    record_audit("pod.share_enabled")
    redirect_to pod_path(@pod), notice: "Pod share link enabled."
  end

  def destroy
    @pod.revoke_share!
    record_audit("pod.share_revoked")
    redirect_to pod_path(@pod), notice: "Pod share link revoked."
  end

  private
    def current_user
      Current.session.user
    end

    def load_pod
      @pod = current_user.pods.find(params[:pod_id])
    end

    def record_audit(event_name)
      AuditEvent.create!(
        user: current_user,
        auditable: @pod,
        event_name: event_name,
        occurred_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { pod_id: @pod.id, pod_name: @pod.name }
      )
    end
end
