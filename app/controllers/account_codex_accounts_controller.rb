class AccountCodexAccountsController < ApplicationController
  before_action :load_codex_account

  def destroy
    if @codex_account.nil?
      redirect_to account_path, alert: "No Codex account is connected."
      return
    end

    @codex_account.disconnect!
    Codex::UserHome.purge!(Current.session.user)
    record_audit("codex.disconnected")
    redirect_to account_path, notice: "Codex account disconnected.", status: :see_other
  end

  def logout
    if @codex_account.nil?
      redirect_to account_path, alert: "No Codex account is connected."
      return
    end

    connections.logout
    record_audit("codex.logged_out")
    redirect_to account_path, notice: "Signed out of Codex and cleared local credentials.", status: :see_other
  rescue Codex::AppServerClient::Error => error
    flash[:alert] = "Codex sign-out failed: #{error.message}"
    redirect_to account_path
  end

  def refresh
    if @codex_account.nil? || !@codex_account.connected?
      redirect_to account_path, alert: "Connect a Codex account before refreshing status."
      return
    end

    connections.refresh_status
    redirect_to account_path, notice: "Codex account status refreshed."
  rescue Codex::AppServerClient::Error => error
    flash[:alert] = "Codex status refresh failed: #{error.message}"
    redirect_to account_path
  end

  private
    def load_codex_account
      @codex_account = Current.session.user.codex_account
    end

    def connections
      @connections ||= Codex::AccountConnections.for(Current.session.user)
    end

    def record_audit(event_name)
      AuditEvent.create!(
        user: Current.session.user,
        event_name: event_name,
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
