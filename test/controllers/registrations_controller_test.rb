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
            timezone: "America/Los_Angeles",
            preferred_units: "metric"
          }
        }
      end
    end

    user = User.find_by!(email_address: "new-player@example.com")

    assert_redirected_to new_session_path(email_address: user.email_address)
    assert_not user.email_verified?
    assert_not_nil user.email_verification_sent_at
    assert_equal "America/Los_Angeles", user.timezone
    assert_equal "metric", user.preferred_units
    assert_nil cookies[:session_id]
  end

  test "create defaults timezone and units when the browser did not provide them" do
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
          email_address: "no-js@example.com",
          password: "correct horse battery staple",
          password_confirmation: "correct horse battery staple"
        }
      }
    end

    user = User.find_by!(email_address: "no-js@example.com")
    assert_equal "UTC", user.timezone
    assert_equal "imperial", user.preferred_units
  end

  test "create falls back to defaults when submitted timezone or units are unknown" do
    post registration_path, params: {
      user: {
        email_address: "weird-locale@example.com",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple",
        timezone: "Mars/Olympus_Mons",
        preferred_units: "furlongs"
      }
    }

    user = User.find_by!(email_address: "weird-locale@example.com")
    assert_equal "UTC", user.timezone
    assert_equal "imperial", user.preferred_units
  end

  test "create renders validation errors without sending email" do
    assert_no_difference "User.count" do
      assert_enqueued_emails 0 do
        post registration_path, params: {
          user: {
            email_address: "not-an-email",
            password: "short",
            password_confirmation: "different"
          }
        }
      end
    end

    assert_response :unprocessable_entity
  end
end
