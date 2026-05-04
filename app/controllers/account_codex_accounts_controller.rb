class AccountCodexAccountsController < ApplicationController
  before_action :load_codex_account

  def destroy
    if @codex_account.nil?
      redirect_to account_path, alert: "No Codex account is connected."
      return
    end

    @codex_account.disconnect!
    record_disconnect
    redirect_to account_path, notice: "Codex account disconnected.", status: :see_other
  end

  private
    def load_codex_account
      @codex_account = Current.session.user.codex_account
    end

    def record_disconnect
      AuditEvent.create!(
        user: Current.session.user,
        event_name: "codex.disconnected",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        auditable: @codex_account,
        metadata: {
          auth_mode: @codex_account.auth_mode,
          displayed_email: @codex_account.displayed_email,
          plan_type: @codex_account.plan_type
        }
      )
    end
end
