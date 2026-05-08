class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @user = User.new
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
      params.require(:user)
            .permit(:email_address, :password, :password_confirmation, :display_name, :timezone, :preferred_units)
            .then { |attrs| attrs.merge(timezone: resolved_timezone(attrs[:timezone]), preferred_units: resolved_units(attrs[:preferred_units])) }
    end

    def resolved_timezone(value)
      return value if value.present? && ActiveSupport::TimeZone[value].present?
      "UTC"
    end

    def resolved_units(value)
      return value if User::PREFERRED_UNITS.include?(value)
      "imperial"
    end
end
