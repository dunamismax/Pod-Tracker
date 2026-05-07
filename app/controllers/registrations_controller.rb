class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @user = User.new(timezone: "UTC", preferred_units: "imperial")
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      Accounts::EmailVerificationDelivery.call(@user)
      redirect_to new_session_path(email_address: @user.email_address), notice: "Account created. Check your email to verify your address."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def registration_params
      params.require(:user).permit(:email_address, :password, :password_confirmation, :display_name, :timezone, :preferred_units)
    end
end
