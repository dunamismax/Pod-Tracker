require "test_helper"

class AccountCodexAccountsControllerTest < ActionDispatch::IntegrationTest
  class FakeClient
    def initialize(scripts = {}, raises_on: {})
      @scripts = scripts
      @raises_on = raises_on
      @calls = []
    end

    attr_reader :calls

    def respond(operation, payload)
      @scripts[operation] = payload
    end

    %i[start_chatgpt_browser_login start_chatgpt_device_login poll_chatgpt_login cancel_chatgpt_login logout_chatgpt get_auth_status].each do |method|
      define_method(method) do |**kwargs|
        @calls << [ method, kwargs ]
        if (raise_with = @raises_on[method])
          raise raise_with
        end
        @scripts.fetch(method) { raise "Unscripted Codex client call: #{method}" }
      end
    end
  end

  setup do
    @user = users(:one)
    @previous_factory = Codex::AccountConnections.client_factory
  end

  teardown do
    Codex::AccountConnections.client_factory = @previous_factory
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

  test "logout signs out of Codex and clears local credentials" do
    @user.codex_account&.destroy
    account = @user.create_codex_account!(
      auth_mode: "chatgpt_browser",
      status: "connected",
      displayed_email: "one-codex@example.com",
      plan_type: "ChatGPT Plus",
      encrypted_credential_payload: "secret-token"
    )
    client = FakeClient.new
    client.respond(:logout_chatgpt, { "ok" => true })
    Codex::AccountConnections.client_factory = -> { client }
    sign_in_as(@user)

    post logout_account_codex_account_path
    assert_redirected_to account_path
    assert_equal "Signed out of Codex and cleared local credentials.", flash[:notice]

    account.reload
    assert_equal "disconnected", account.status
    assert_nil account.encrypted_credential_payload
    assert_equal :logout_chatgpt, client.calls.first.first

    event = AuditEvent.where(event_name: "codex.logged_out").last
    assert_not_nil event
  end

  test "refresh updates rate-limit snapshot, plan, and last_synced_at" do
    @user.codex_account&.destroy
    account = @user.create_codex_account!(
      auth_mode: "chatgpt_browser",
      status: "connected",
      encrypted_credential_payload: "secret-token"
    )
    client = FakeClient.new
    client.respond(:get_auth_status, {
      "displayedEmail" => "fresh@example.com",
      "planType" => "team",
      "rateLimit" => { "primaryUsedPercent" => 12 }
    })
    Codex::AccountConnections.client_factory = -> { client }
    sign_in_as(@user)

    post refresh_account_codex_account_path
    assert_redirected_to account_path
    assert_equal "Codex account status refreshed.", flash[:notice]

    account.reload
    assert_equal "fresh@example.com", account.displayed_email
    assert_equal "team", account.plan_type
    assert_equal({ "primaryUsedPercent" => 12 }, account.rate_limit_snapshot)
  end

end
