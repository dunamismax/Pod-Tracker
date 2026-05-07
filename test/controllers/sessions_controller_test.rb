require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "create with verified account starts session" do
    user = users(:one)

    post session_path, params: { email_address: user.email_address, password: "password" }

    assert_redirected_to root_url
    assert_not_nil cookies[:session_id]
  end

  test "create with unverified account resends verification and refuses session" do
    user = users(:two)

    assert_enqueued_email_with UserMailer, :verify_email, args: [ user ] do
      post session_path, params: { email_address: user.email_address, password: "password" }
    end

    assert_redirected_to new_session_path(email_address: user.email_address)
    assert_match(/verify your address/, flash[:alert])
    assert_not_nil user.reload.email_verification_sent_at
    assert_nil cookies[:session_id]
  end
end
