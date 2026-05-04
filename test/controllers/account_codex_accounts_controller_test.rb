require "test_helper"

class AccountCodexAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "requires authentication" do
    delete account_codex_account_path
    assert_redirected_to new_session_path
  end

  test "redirects with alert when no codex account is connected" do
    @user.codex_account&.destroy
    sign_in_as(@user)

    delete account_codex_account_path
    assert_redirected_to account_path
    assert_equal "No Codex account is connected.", flash[:alert]
  end

  test "disconnects the codex account, clears credentials, and records an audit event" do
    @user.codex_account&.destroy
    account = @user.create_codex_account!(
      auth_mode: "chatgpt_browser",
      status: "connected",
      displayed_email: "one-codex@example.com",
      plan_type: "ChatGPT Plus",
      encrypted_credential_payload: "secret-token",
      credential_metadata: { token_kind: "chatgpt_session" }
    )
    sign_in_as(@user)

    delete account_codex_account_path
    assert_redirected_to account_path
    assert_equal "Codex account disconnected.", flash[:notice]

    account.reload
    assert_equal "disconnected", account.status
    assert_nil account.encrypted_credential_payload
    assert_equal({}, account.credential_metadata)

    event = AuditEvent.where(event_name: "codex.disconnected").last
    assert_not_nil event
    assert_equal @user.id, event.user_id
    assert_equal "chatgpt_browser", event.metadata["auth_mode"]
    assert_equal "one-codex@example.com", event.metadata["displayed_email"]
    assert_equal "ChatGPT Plus", event.metadata["plan_type"]
  end
end
