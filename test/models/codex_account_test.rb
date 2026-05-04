require "test_helper"

class CodexAccountTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.codex_account&.destroy
  end

  test "validates auth_mode and status" do
    account = CodexAccount.new(user: @user, auth_mode: "bogus", status: "weird")
    assert_not account.valid?
    assert_includes account.errors[:auth_mode], "is not included in the list"
    assert_includes account.errors[:status], "is not included in the list"
  end

  test "rejects more than one codex account per user" do
    CodexAccount.create!(user: @user, auth_mode: "chatgpt_browser", status: "connected")
    second = CodexAccount.new(user: @user, auth_mode: "chatgpt_device_code", status: "pending")
    assert_not second.valid?
    assert_includes second.errors[:user_id], "has already been taken"
  end

  test "encrypts the credential payload column" do
    account = CodexAccount.create!(
      user: @user,
      auth_mode: "chatgpt_browser",
      status: "connected",
      encrypted_credential_payload: "secret-token"
    )

    raw = CodexAccount.connection.select_value(
      CodexAccount.send(:sanitize_sql_array, [
        "SELECT encrypted_credential_payload FROM codex_accounts WHERE id = ?", account.id
      ])
    )

    assert raw.present?
    assert_no_match(/secret-token/, raw)
    assert_equal "secret-token", account.reload.encrypted_credential_payload
  end

  test "disconnect! clears credentials and stamps disconnected_at" do
    account = CodexAccount.create!(
      user: @user,
      auth_mode: "chatgpt_browser",
      status: "connected",
      encrypted_credential_payload: "secret-token",
      credential_metadata: { token_kind: "chatgpt_session" },
      rate_limit_snapshot: { primary_used_percent: 5 }
    )

    travel_to Time.utc(2026, 5, 4, 18, 0, 0) do
      account.disconnect!
    end
    account.reload

    assert_equal "disconnected", account.status
    assert_nil account.encrypted_credential_payload
    assert_equal({}, account.credential_metadata)
    assert_equal({}, account.rate_limit_snapshot)
    assert_equal Time.utc(2026, 5, 4, 18, 0, 0), account.disconnected_at.utc
  end

  test "export_payload omits credential payload but exposes metadata keys" do
    account = CodexAccount.create!(
      user: @user,
      auth_mode: "chatgpt_browser",
      status: "connected",
      encrypted_credential_payload: "secret-token",
      credential_metadata: { token_kind: "chatgpt_session", refresh_hint: "rotate-soon" }
    )

    payload = account.export_payload

    assert_equal "chatgpt_browser", payload[:auth_mode]
    assert_equal "connected", payload[:status]
    assert payload[:credential_present]
    assert_equal %w[refresh_hint token_kind], payload[:credential_metadata_keys]
    refute_includes payload.keys, :encrypted_credential_payload
    refute_includes payload.values.compact.map(&:to_s).join, "secret-token"
  end

  test "destroying the user destroys the codex account" do
    user = User.create!(
      email_address: "codex-burner@example.com",
      password: "supersecret",
      password_confirmation: "supersecret"
    )
    user.create_codex_account!(auth_mode: "chatgpt_browser", status: "connected")

    assert_difference -> { CodexAccount.count }, -1 do
      user.destroy!
    end
  end
end
