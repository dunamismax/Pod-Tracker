class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @user = User.new(timezone: "UTC", preferred_units: "imperial")
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      send_email_verification(@user)
      start_new_session_for(@user)
      redirect_to root_path, notice: "Account created. Check your email to verify your address."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def registration_params
      params.require(:user).permit(:email_address, :password, :password_confirmation, :display_name, :timezone, :preferred_units)
    end

    def send_email_verification(user)
      UserMailer.verify_email(user).deliver_later
      user.update_columns(email_verification_sent_at: Time.current)
    end
end
