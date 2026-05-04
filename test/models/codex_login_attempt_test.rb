require "test_helper"

class CodexLoginAttemptTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "validates auth_mode and status" do
    attempt = CodexLoginAttempt.new(user: @user, auth_mode: "bogus", status: "weird")
    assert_not attempt.valid?
    assert_includes attempt.errors[:auth_mode], "is not included in the list"
    assert_includes attempt.errors[:status], "is not included in the list"
  end

  test "defaults started_at when not supplied" do
    attempt = CodexLoginAttempt.new(user: @user, auth_mode: "chatgpt_browser", status: "pending")
    assert attempt.valid?, attempt.errors.full_messages.to_sentence
    assert_not_nil attempt.started_at
  end

  test "active scope returns only pending and awaiting_user" do
    pending = CodexLoginAttempt.create!(user: @user, auth_mode: "chatgpt_browser", status: "pending")
    awaiting = CodexLoginAttempt.create!(user: @user, auth_mode: "chatgpt_browser", status: "awaiting_user")
    completed = CodexLoginAttempt.create!(user: @user, auth_mode: "chatgpt_browser", status: "completed", completed_at: Time.current)

    active_ids = CodexLoginAttempt.active.pluck(:id)
    assert_includes active_ids, pending.id
    assert_includes active_ids, awaiting.id
    refute_includes active_ids, completed.id
  end

  test "mark_awaiting_user! stores handle and prompt detail" do
    attempt = CodexLoginAttempt.create!(user: @user, auth_mode: "chatgpt_device_code", status: "pending")
    expires = Time.utc(2026, 5, 4, 22, 0, 0)
    attempt.mark_awaiting_user!(
      handle: "abc-123",
      verification_uri: "https://chatgpt.com/device",
      user_code: "ABCD-EFGH",
      expires_at: expires,
      now: Time.utc(2026, 5, 4, 21, 0, 0)
    )

    assert_equal "awaiting_user", attempt.status
    assert_equal "abc-123", attempt.external_handle
    assert_equal "https://chatgpt.com/device", attempt.verification_uri
    assert_equal "ABCD-EFGH", attempt.user_code
    assert_equal expires, attempt.expires_at.utc
    assert_equal Time.utc(2026, 5, 4, 21, 0, 0), attempt.awaiting_user_at.utc
  end

  test "expired? respects status and expires_at" do
    attempt = CodexLoginAttempt.create!(
      user: @user,
      auth_mode: "chatgpt_browser",
      status: "awaiting_user",
      expires_at: 5.minutes.from_now
    )
    refute attempt.expired?

    attempt.update!(expires_at: 5.minutes.ago)
    assert attempt.expired?

    attempt.update!(status: "expired", expires_at: 5.minutes.from_now)
    assert attempt.expired?
  end

  test "destroying user destroys login attempts" do
    user = User.create!(
      email_address: "loginburner@example.com",
      password: "supersecret",
      password_confirmation: "supersecret"
    )
    user.codex_login_attempts.create!(auth_mode: "chatgpt_browser", status: "pending")

    assert_difference -> { CodexLoginAttempt.count }, -1 do
      user.destroy!
    end
  end
end
