require "test_helper"

class AccountCodexLoginsControllerTest < ActionDispatch::IntegrationTest
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
    @user.codex_account&.destroy
    @user.codex_login_attempts.destroy_all
    @client = FakeClient.new
    @previous_factory = Codex::AccountConnections.client_factory
    Codex::AccountConnections.client_factory = -> { @client }
    sign_in_as(@user)
  end

  teardown do
    Codex::AccountConnections.client_factory = @previous_factory
  end

  test "new requires authentication" do
    sign_out
    get new_account_codex_login_path
    assert_redirected_to new_session_path
  end

  test "new redirects to active attempt when one exists" do
    attempt = @user.codex_login_attempts.create!(
      auth_mode: "chatgpt_browser",
      status: "awaiting_user",
      external_handle: "abc"
    )
    get new_account_codex_login_path
    assert_redirected_to account_codex_login_path(attempt)
  end

  test "new renders connect choices" do
    get new_account_codex_login_path
    assert_response :success
    assert_select "h1", text: "Connect Codex account"
    assert_select "form input[name=auth_mode][value=chatgpt_browser]"
    assert_select "form input[name=auth_mode][value=chatgpt_device_code]"
  end

  test "create starts a browser login attempt and redirects to its show page" do
    @client.respond(:start_chatgpt_browser_login, {
      "loginId" => "abc",
      "loginUrl" => "https://chatgpt.com/login/abc",
      "expiresAt" => "2026-05-04T22:00:00Z"
    })

    post account_codex_logins_path, params: { auth_mode: "chatgpt_browser" }

    attempt = @user.codex_login_attempts.recent_first.first
    assert_redirected_to account_codex_login_path(attempt)
    assert_equal "awaiting_user", attempt.status
    assert_equal "https://chatgpt.com/login/abc", attempt.login_url

    event = AuditEvent.where(event_name: "codex.login_started").last
    assert_not_nil event
    assert_equal "chatgpt_browser", event.metadata["auth_mode"]
  end

  test "create starts a device-code login attempt" do
    @client.respond(:start_chatgpt_device_login, {
      "loginId" => "dev-1",
      "userCode" => "WXYZ-1234",
      "verificationUri" => "https://chatgpt.com/device"
    })

    post account_codex_logins_path, params: { auth_mode: "chatgpt_device_code" }

    attempt = @user.codex_login_attempts.recent_first.first
    assert_redirected_to account_codex_login_path(attempt)
    assert_equal "WXYZ-1234", attempt.user_code
    assert_equal "https://chatgpt.com/device", attempt.verification_uri
  end

  test "create rejects unknown auth modes" do
    post account_codex_logins_path, params: { auth_mode: "api_key" }
    assert_redirected_to new_account_codex_login_path
    assert_match(/browser sign-in or device-code/, flash[:alert])
    assert_equal 0, @user.codex_login_attempts.count
  end

  test "create surfaces transport errors as flash alerts" do
    @client = FakeClient.new(raises_on: { start_chatgpt_browser_login: Codex::AppServerClient::TransportError.new("offline") })
    Codex::AccountConnections.client_factory = -> { @client }

    post account_codex_logins_path, params: { auth_mode: "chatgpt_browser" }
    assert_redirected_to new_account_codex_login_path
    assert_match(/offline/, flash[:alert])

    attempt = @user.codex_login_attempts.recent_first.first
    assert_equal "failed", attempt.status
  end

  test "show renders awaiting_user attempt with browser login URL" do
    attempt = @user.codex_login_attempts.create!(
      auth_mode: "chatgpt_browser",
      status: "awaiting_user",
      external_handle: "abc",
      login_url: "https://chatgpt.com/login/abc",
      awaiting_user_at: Time.current
    )

    get account_codex_login_path(attempt)
    assert_response :success
    assert_select "a[href=?]", "https://chatgpt.com/login/abc"
  end

  test "show renders device-code attempt with verification URI and user code" do
    attempt = @user.codex_login_attempts.create!(
      auth_mode: "chatgpt_device_code",
      status: "awaiting_user",
      external_handle: "dev-1",
      verification_uri: "https://chatgpt.com/device",
      user_code: "WXYZ-1234",
      awaiting_user_at: Time.current
    )

    get account_codex_login_path(attempt)
    assert_response :success
    assert_select "a[href=?]", "https://chatgpt.com/device"
    assert_select "p", text: "WXYZ-1234"
  end

  test "show is scoped to the signed-in user" do
    other = users(:two)
    other.codex_login_attempts.destroy_all
    attempt = other.codex_login_attempts.create!(
      auth_mode: "chatgpt_browser",
      status: "awaiting_user",
      external_handle: "other"
    )

    get account_codex_login_path(attempt)
    assert_response :not_found
  end

  test "poll completes the attempt and redirects to account on completion" do
    attempt = @user.codex_login_attempts.create!(
      auth_mode: "chatgpt_browser",
      status: "awaiting_user",
      external_handle: "abc"
    )
    @client.respond(:poll_chatgpt_login, {
      "state" => "completed",
      "credential" => "encrypted-blob",
      "displayedEmail" => "demo@example.com",
      "planType" => "plus"
    })

    post poll_account_codex_login_path(attempt)
    assert_redirected_to account_path
    assert_equal "Codex account connected.", flash[:notice]

    assert @user.reload.codex_account.connected?

    event = AuditEvent.where(event_name: "codex.login_completed").last
    assert_not_nil event
    assert_equal "demo@example.com", event.metadata["displayed_email"]
  end

  test "poll keeps awaiting_user attempts on the show page" do
    attempt = @user.codex_login_attempts.create!(
      auth_mode: "chatgpt_browser",
      status: "awaiting_user",
      external_handle: "abc"
    )
    @client.respond(:poll_chatgpt_login, { "state" => "awaiting_user" })

    post poll_account_codex_login_path(attempt)
    assert_redirected_to account_codex_login_path(attempt)
    assert_equal "awaiting_user", attempt.reload.status
  end

  test "poll redirects without polling when attempt is no longer active" do
    attempt = @user.codex_login_attempts.create!(
      auth_mode: "chatgpt_browser",
      status: "completed",
      external_handle: "abc",
      completed_at: 1.minute.ago
    )

    post poll_account_codex_login_path(attempt)
    assert_redirected_to account_codex_login_path(attempt)
    assert_equal [], @client.calls
  end

  test "destroy cancels the attempt and records an audit event" do
    attempt = @user.codex_login_attempts.create!(
      auth_mode: "chatgpt_browser",
      status: "awaiting_user",
      external_handle: "abc"
    )
    @client.respond(:cancel_chatgpt_login, { "ok" => true })

    delete account_codex_login_path(attempt)
    assert_redirected_to account_path
    assert_equal "cancelled", attempt.reload.status

    event = AuditEvent.where(event_name: "codex.login_cancelled").last
    assert_not_nil event
    assert_equal "chatgpt_browser", event.metadata["auth_mode"]
  end

  test "destroy does not call cancel when attempt is already terminal" do
    attempt = @user.codex_login_attempts.create!(
      auth_mode: "chatgpt_browser",
      status: "expired",
      external_handle: "abc",
      failed_at: 1.minute.ago
    )

    delete account_codex_login_path(attempt)
    assert_redirected_to account_path
    assert_equal [], @client.calls
  end
end
