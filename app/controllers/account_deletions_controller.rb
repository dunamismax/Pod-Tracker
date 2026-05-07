class AccountDeletionsController < ApplicationController
  before_action :load_user

  def new
  end

  def destroy
    if @user.authenticate(params[:current_password].to_s)
      record_deletion
      terminate_session
      Codex::UserHome.purge!(@user)
      @user.destroy
      redirect_to new_session_path, notice: "Account deleted.", status: :see_other
    else
      flash.now[:alert] = "Password did not match."
      render :new, status: :unprocessable_entity
    end
  end

  private
    def load_user
      @user = Current.session.user
    end

    def record_deletion
      AuditEvent.create!(
        user: @user,
        event_name: "account.deleted",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          email_address: @user.email_address,
          display_name: @user.display_name,
          deck_count: @user.decks.count,
          analysis_run_count: @user.analysis_runs.count,
          pod_count: @user.pods.count
        }
      )
    end
end
