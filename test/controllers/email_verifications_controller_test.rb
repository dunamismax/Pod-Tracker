require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:two) }

  test "show with valid token marks user verified" do
    token = @user.generate_token_for(:email_verification)
    get email_verification_path(token: token)
    assert_redirected_to root_path
    assert @user.reload.email_verified?
  end

  test "show with invalid token redirects with alert" do
    get email_verification_path(token: "garbage")
    assert_redirected_to root_path
    assert_match(/invalid or has expired/, flash[:alert])
  end

  test "show indicates already-verified accounts" do
    verified = users(:one)
    token = verified.generate_token_for(:email_verification)
    get email_verification_path(token: token)
    assert_redirected_to root_path
    assert_match(/already verified/i, flash[:notice])
  end

  test "create resends verification email when signed in" do
    sign_in_as(@user)
    assert_enqueued_email_with UserMailer, :verify_email, args: [ @user ] do
      post email_verifications_path
    end
    assert_redirected_to account_path
    assert_not_nil @user.reload.email_verification_sent_at
  end

  test "create on verified account skips mail" do
    verified = users(:one)
    sign_in_as(verified)
    assert_enqueued_emails 0 do
      post email_verifications_path
    end
    assert_redirected_to account_path
  end

  test "create requires authentication" do
    post email_verifications_path
    assert_redirected_to new_session_path
  end
end
