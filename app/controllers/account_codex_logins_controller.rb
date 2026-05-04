class AccountCodexLoginsController < ApplicationController
  before_action :load_user

  def new
    @active_attempt = active_attempt
    redirect_to account_codex_login_path(@active_attempt) and return if @active_attempt
  end

  def create
    auth_mode = params[:auth_mode].to_s
    unless Codex::AccountConnections::BROWSER_AUTH_MODE == auth_mode || Codex::AccountConnections::DEVICE_CODE_AUTH_MODE == auth_mode
      redirect_to new_account_codex_login_path, alert: "Pick browser sign-in or device-code sign-in to continue." and return
    end

    result = connections.start_login(auth_mode)
    record_audit("codex.login_started", auditable: result.attempt, metadata: { auth_mode: auth_mode })
    redirect_to account_codex_login_path(result.attempt), notice: notice_for_started(auth_mode)
  rescue Codex::AppServerClient::Error => error
    flash[:alert] = "Codex sign-in could not start: #{error.message}"
    redirect_to new_account_codex_login_path
  end

  def show
    @attempt = scope.find(params[:id])
  end

  def poll
    @attempt = scope.find(params[:id])

    unless @attempt.active?
      redirect_to account_codex_login_path(@attempt) and return
    end

    result = connections.poll_login(@attempt)
    case result.state
    when "completed"
      record_audit("codex.login_completed", auditable: @attempt, metadata: completion_metadata(result.codex_account))
      redirect_to account_path, notice: "Codex account connected."
    when "awaiting_user"
      redirect_to account_codex_login_path(@attempt), notice: "Still waiting for ChatGPT to confirm sign-in."
    when "cancelled", "expired", "failed"
      redirect_to account_codex_login_path(@attempt), alert: alert_for_terminal(result.state, @attempt)
    else
      redirect_to account_codex_login_path(@attempt), alert: "Codex sign-in returned an unexpected state."
    end
  rescue Codex::AppServerClient::Error => error
    flash[:alert] = "Codex sign-in poll failed: #{error.message}"
    redirect_to account_codex_login_path(@attempt)
  end

  def destroy
    @attempt = scope.find(params[:id])

    if @attempt.active?
      connections.cancel_login(@attempt)
      record_audit("codex.login_cancelled", auditable: @attempt, metadata: { auth_mode: @attempt.auth_mode })
    end

    redirect_to account_path, notice: "Codex sign-in cancelled.", status: :see_other
  end

  private
    def load_user
      @user = Current.session.user
    end

    def scope
      @user.codex_login_attempts
    end

    def active_attempt
      scope.active.recent_first.first
    end

    def connections
      @connections ||= Codex::AccountConnections.for(@user)
    end

    def notice_for_started(auth_mode)
      if auth_mode == Codex::AccountConnections::BROWSER_AUTH_MODE
        "Open the browser sign-in URL to finish connecting your ChatGPT account."
      else
        "Visit the verification URL and enter the device code to finish connecting your ChatGPT account."
      end
    end

    def alert_for_terminal(state, attempt)
      case state
      when "cancelled" then "Codex sign-in was cancelled."
      when "expired"   then "Codex sign-in expired. Start a new sign-in to try again."
      when "failed"    then "Codex sign-in failed: #{attempt.failure_message.presence || attempt.failure_code.presence || 'unknown error'}"
      end
    end

    def completion_metadata(account)
      {
        auth_mode: account&.auth_mode,
        displayed_email: account&.displayed_email,
        plan_type: account&.plan_type
      }
    end

    def record_audit(event_name, auditable:, metadata: {})
      AuditEvent.create!(
        user: @user,
        event_name: event_name,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        auditable: auditable,
        metadata: metadata.compact
      )
    end
end
