require "test_helper"

class CodexAccountTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.codex_account&.destroy
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

end
