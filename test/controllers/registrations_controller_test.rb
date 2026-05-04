require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new renders" do
    get new_registration_path
    assert_response :success
    assert_select "h1", text: /Create your account/
  end

  test "create persists user, signs them in, and queues verification email" do
    assert_difference -> { User.count }, 1 do
      assert_enqueued_email_with UserMailer, :verify_email, args: ->(args) { args.first.email_address == "fresh@example.com" } do
        post registration_path, params: {
          user: {
            email_address: "Fresh@example.com",
            password: "supersecret",
            password_confirmation: "supersecret",
            display_name: "Fresh",
            timezone: "UTC",
            preferred_units: "metric"
          }
        }
      end
    end

    user = User.find_by(email_address: "fresh@example.com")
    assert_not_nil user
    assert_equal "Fresh", user.display_name
    assert_not_nil user.email_verification_sent_at
    assert_redirected_to root_path
    assert cookies[:session_id].present?
  end

  test "create rejects mismatched passwords" do
    assert_no_difference -> { User.count } do
      post registration_path, params: {
        user: {
          email_address: "mismatch@example.com",
          password: "supersecret",
          password_confirmation: "different",
          timezone: "UTC",
          preferred_units: "imperial"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "create rejects duplicate email" do
    existing = User.take
    assert_no_difference -> { User.count } do
      post registration_path, params: {
        user: {
          email_address: existing.email_address,
          password: "supersecret",
          password_confirmation: "supersecret",
          timezone: "UTC",
          preferred_units: "imperial"
        }
      }
    end
    assert_response :unprocessable_entity
  end
end
