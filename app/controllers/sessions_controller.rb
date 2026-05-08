class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      if user.email_verified?
        start_new_session_for user
        redirect_to after_authentication_url
      else
        Accounts::EmailVerificationDelivery.call(user)
        redirect_to new_session_path(email_address: user.email_address),
                    alert: "Check your email to verify your address before signing in."
      end
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path,
                status: :see_other,
                flash: { clear_page_cache: true }
  end
end
