class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: %i[show]
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to account_path, alert: "Verification email rate limit reached. Try again later." }

  def show
    user = User.find_by_token_for(:email_verification, params[:token])

    if user.nil?
      redirect_to root_path, alert: "Verification link is invalid or has expired."
    elsif user.email_verified?
      start_new_session_for(user) unless Current.session&.user == user
      redirect_to root_path, notice: "Email already verified."
    else
      user.update!(email_verified_at: Time.current)
      start_new_session_for(user) unless Current.session&.user == user
      redirect_to root_path, notice: "Email verified."
    end
  end

  def create
    user = Current.session.user

    if user.email_verified?
      redirect_to account_path, notice: "Your email is already verified."
    else
      Accounts::EmailVerificationDelivery.call(user)
      redirect_to account_path, notice: "Verification email sent."
    end
  end
end
