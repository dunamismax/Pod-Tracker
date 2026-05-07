require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "create enqueues verification email and leaves account signed out" do
    assert_difference "User.count", 1 do
      assert_enqueued_emails 1 do
        post registration_path, params: {
          user: {
            email_address: "new-player@example.com",
            display_name: "New Player",
            password: "correct horse battery staple",
            password_confirmation: "correct horse battery staple",
            timezone: "UTC",
            preferred_units: "imperial"
          }
        }
      end
    end

    user = User.find_by!(email_address: "new-player@example.com")

    assert_redirected_to new_session_path(email_address: user.email_address)
    assert_not user.email_verified?
    assert_not_nil user.email_verification_sent_at
    assert_nil cookies[:session_id]
  end

  test "create renders validation errors without sending email" do
    assert_no_difference "User.count" do
      assert_enqueued_emails 0 do
        post registration_path, params: {
          user: {
            email_address: "not-an-email",
            password: "short",
            password_confirmation: "different",
            timezone: "UTC",
            preferred_units: "imperial"
          }
        }
      end
    end

    assert_response :unprocessable_entity
  end
end
