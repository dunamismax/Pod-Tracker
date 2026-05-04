class AccountProviderLinksController < ApplicationController
  before_action :load_user

  def new
    @provider_link = @user.provider_links.new(provider: params[:provider])
  end

  def create
    @provider_link = @user.provider_links.new(provider_link_params)
    if @provider_link.save
      record_audit("provider_link.created")
      redirect_to account_path, notice: "Provider link added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    provider_link = @user.provider_links.find(params[:id])
    metadata = {
      provider: provider_link.provider,
      handle: provider_link.handle,
      profile_url: provider_link.profile_url
    }
    provider_link.destroy
    record_audit("provider_link.removed", metadata: metadata)
    redirect_to account_path, notice: "Provider link removed."
  end

  private
    def load_user
      @user = Current.session.user
    end

    def provider_link_params
      params.require(:user_provider_link).permit(:provider, :handle, :profile_url, :label, :notes)
    end

    def record_audit(name, metadata: nil)
      payload = metadata || {
        provider: @provider_link.provider,
        handle: @provider_link.handle,
        profile_url: @provider_link.profile_url
      }
      AuditEvent.create!(
        user: @user,
        event_name: name,
        occurred_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: payload.compact
      )
    end
end
