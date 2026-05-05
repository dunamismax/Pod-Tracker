require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "normalizes display_name to nil when blank" do
    user = User.new(display_name: "   ")
    assert_nil user.display_name
  end

  test "email_verified? reflects email_verified_at" do
    user = build_user
    assert_not user.email_verified?
    user.email_verified_at = Time.current
    assert user.email_verified?
  end

  test "attribution_name prefers display_name" do
    user = build_user(display_name: "Spike")
    assert_equal "Spike", user.attribution_name
    user.display_name = nil
    assert_equal user.email_address, user.attribution_name
  end

  test "email_verification token round-trips and invalidates on email change" do
    user = users(:one)
    token = user.generate_token_for(:email_verification)
    assert_equal user, User.find_by_token_for(:email_verification, token)

    user.update!(email_address: "rotated@example.com")
    assert_nil User.find_by_token_for(:email_verification, token)
  end

  private
    def build_user(attrs = {})
      User.new({
        email_address: "new@example.com",
        password: "supersecret",
        password_confirmation: "supersecret",
        timezone: "UTC",
        preferred_units: "imperial"
      }.merge(attrs))
    end
end
