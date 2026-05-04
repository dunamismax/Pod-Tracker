require "test_helper"

module Codex
  class AccountConnectionsTest < ActiveSupport::TestCase
    class FakeClient
      attr_reader :calls

      def initialize(scripts = {}, raises_on: {})
        @scripts = scripts
        @raises_on = raises_on
        @calls = []
      end

      def respond(operation, payload)
        @scripts[operation] = payload
      end

      %i[start_chatgpt_browser_login start_chatgpt_device_login poll_chatgpt_login cancel_chatgpt_login logout_chatgpt get_auth_status].each do |method|
        define_method(method) do |**kwargs|
          @calls << [ method, kwargs ]
          if (raise_with = @raises_on[method])
            raise raise_with
          end
          @scripts.fetch(method) do
            raise "Unscripted Codex client call: #{method}"
          end
        end
      end
    end

    setup do
      @user = users(:one)
      @user.codex_account&.destroy
      @user.codex_login_attempts.destroy_all
      @clock_time = Time.utc(2026, 5, 4, 21, 0, 0)
      @clock = -> { @clock_time }
      @client = FakeClient.new
    end

    def service
      AccountConnections.new(@user, client: @client, clock: @clock)
    end

    test "start_login(browser) creates an awaiting_user attempt with the App Server URL" do
      @client.respond(:start_chatgpt_browser_login, {
        "loginId" => "abc",
        "loginUrl" => "https://chatgpt.com/login/abc",
        "expiresAt" => "2026-05-04T22:00:00Z"
      })

      result = service.start_login("chatgpt_browser")
      attempt = result.attempt

      assert_equal "awaiting_user", result.state
      assert_equal "awaiting_user", attempt.status
      assert_equal "abc", attempt.external_handle
      assert_equal "https://chatgpt.com/login/abc", attempt.login_url
      assert_equal Time.utc(2026, 5, 4, 22, 0, 0), attempt.expires_at.utc
      assert_equal :start_chatgpt_browser_login, @client.calls.first.first
    end

    test "start_login(device_code) records user_code and verification_uri" do
      @client.respond(:start_chatgpt_device_login, {
        "loginId" => "dev-1",
        "userCode" => "WXYZ-1234",
        "verificationUri" => "https://chatgpt.com/device"
      })

      result = service.start_login("chatgpt_device_code")
      attempt = result.attempt

      assert_equal "WXYZ-1234", attempt.user_code
      assert_equal "https://chatgpt.com/device", attempt.verification_uri
      assert_equal "chatgpt_device_code", attempt.auth_mode
    end

    test "start_login rejects unknown auth modes" do
      assert_raises(AccountConnections::InvalidAuthMode) { service.start_login("api_key") }
    end

    test "start_login cancels any prior active attempt before starting a new one" do
      stale = @user.codex_login_attempts.create!(
        auth_mode: "chatgpt_browser",
        status: "awaiting_user",
        external_handle: "stale-handle"
      )

      @client.respond(:cancel_chatgpt_login, { "ok" => true })
      @client.respond(:start_chatgpt_browser_login, {
        "loginId" => "fresh",
        "loginUrl" => "https://chatgpt.com/login/fresh"
      })

      service.start_login("chatgpt_browser")

      cancel_call = @client.calls.find { |op, _| op == :cancel_chatgpt_login }
      assert cancel_call, "expected cancel_chatgpt_login to be invoked for stale attempt"
      assert_equal "stale-handle", cancel_call.last[:login_id]
      assert_equal "cancelled", stale.reload.status
    end

    test "start_login marks attempt failed and re-raises when client errors" do
      @client = FakeClient.new(raises_on: { start_chatgpt_browser_login: AppServerClient::TransportError.new("nope") })
      assert_raises(AppServerClient::TransportError) { service.start_login("chatgpt_browser") }
      attempt = @user.codex_login_attempts.recent_first.first
      assert_equal "failed", attempt.status
      assert_equal "transport_error", attempt.failure_code
    end

    test "poll_login persists credential and returns connected codex account on completion" do
      attempt = @user.codex_login_attempts.create!(
        auth_mode: "chatgpt_browser",
        status: "awaiting_user",
        external_handle: "abc"
      )

      @client.respond(:poll_chatgpt_login, {
        "state" => "completed",
        "credential" => "encrypted-blob",
        "credentialMetadata" => { "tokenKind" => "chatgpt_session" },
        "displayedEmail" => "demo@example.com",
        "planType" => "plus",
        "rateLimit" => { "primaryUsedPercent" => 5 },
        "expiresAt" => "2026-06-04T00:00:00Z"
      })

      result = service.poll_login(attempt)
      account = result.codex_account

      assert_equal "completed", result.state
      assert_equal "completed", attempt.reload.status
      assert account.connected?
      assert_equal "demo@example.com", account.displayed_email
      assert_equal "plus", account.plan_type
      assert_equal "encrypted-blob", account.encrypted_credential_payload
      assert_equal({ "tokenKind" => "chatgpt_session" }, account.credential_metadata)
      assert_equal({ "primaryUsedPercent" => 5 }, account.rate_limit_snapshot)
      assert_equal Time.utc(2026, 6, 4, 0, 0, 0), account.credentials_expire_at.utc
      assert_equal @clock_time, account.connected_at.utc
    end

    test "poll_login leaves attempt awaiting_user when state is awaiting_user" do
      attempt = @user.codex_login_attempts.create!(
        auth_mode: "chatgpt_browser",
        status: "awaiting_user",
        external_handle: "abc"
      )
      @client.respond(:poll_chatgpt_login, { "state" => "awaiting_user" })

      result = service.poll_login(attempt)

      assert_equal "awaiting_user", result.state
      assert_equal "awaiting_user", attempt.reload.status
      assert_equal @clock_time, attempt.last_polled_at.utc
    end

    test "poll_login marks attempt expired when state is expired" do
      attempt = @user.codex_login_attempts.create!(
        auth_mode: "chatgpt_browser",
        status: "awaiting_user",
        external_handle: "abc"
      )
      @client.respond(:poll_chatgpt_login, { "state" => "expired" })

      service.poll_login(attempt)
      assert_equal "expired", attempt.reload.status
    end

    test "poll_login marks attempt failed with provided failure code" do
      attempt = @user.codex_login_attempts.create!(
        auth_mode: "chatgpt_browser",
        status: "awaiting_user",
        external_handle: "abc"
      )
      @client.respond(:poll_chatgpt_login, {
        "state" => "failed",
        "failureCode" => "user_denied",
        "failureMessage" => "user denied login"
      })

      service.poll_login(attempt)
      assert_equal "failed", attempt.reload.status
      assert_equal "user_denied", attempt.failure_code
      assert_equal "user denied login", attempt.failure_message
    end

    test "poll_login refuses inactive attempts" do
      attempt = @user.codex_login_attempts.create!(
        auth_mode: "chatgpt_browser",
        status: "completed",
        completed_at: 1.minute.ago
      )
      assert_raises(AccountConnections::InvalidAttempt) { service.poll_login(attempt) }
    end

    test "cancel_login asks Codex to cancel and marks attempt cancelled" do
      attempt = @user.codex_login_attempts.create!(
        auth_mode: "chatgpt_browser",
        status: "awaiting_user",
        external_handle: "abc"
      )
      @client.respond(:cancel_chatgpt_login, { "ok" => true })

      result = service.cancel_login(attempt)

      assert_equal "cancelled", result.state
      assert_equal "cancelled", attempt.reload.status
      assert_equal :cancel_chatgpt_login, @client.calls.first.first
    end

    test "cancel_login still marks attempt cancelled when remote cancel errors" do
      attempt = @user.codex_login_attempts.create!(
        auth_mode: "chatgpt_browser",
        status: "awaiting_user",
        external_handle: "abc"
      )
      @client = FakeClient.new(raises_on: { cancel_chatgpt_login: AppServerClient::TransportError.new("nope") })

      service.cancel_login(attempt)
      assert_equal "cancelled", attempt.reload.status
    end

    test "logout disconnects local account and calls remote logout" do
      account = @user.create_codex_account!(
        auth_mode: "chatgpt_browser",
        status: "connected",
        encrypted_credential_payload: "secret",
        credential_metadata: { "tokenKind" => "chatgpt_session" },
        rate_limit_snapshot: { "primaryUsedPercent" => 5 },
        connected_at: 1.day.ago
      )

      @client.respond(:logout_chatgpt, { "ok" => true })

      result = service.logout
      account.reload

      assert_equal "disconnected", result.state
      assert_equal "disconnected", account.status
      assert_nil account.encrypted_credential_payload
      assert_equal({}, account.credential_metadata)
      assert_equal({}, account.rate_limit_snapshot)
      assert_equal @clock_time, account.disconnected_at.utc
      assert_equal :logout_chatgpt, @client.calls.first.first
    end

    test "logout still disconnects locally when remote logout errors" do
      account = @user.create_codex_account!(
        auth_mode: "chatgpt_browser",
        status: "connected",
        encrypted_credential_payload: "secret"
      )
      @client = FakeClient.new(raises_on: { logout_chatgpt: AppServerClient::TransportError.new("nope") })

      service.logout
      assert_equal "disconnected", account.reload.status
      assert_nil account.encrypted_credential_payload
    end

    test "logout returns absent state when no codex account exists" do
      result = service.logout
      assert_equal "absent", result.state
      assert_nil result.codex_account
    end

    test "refresh_status updates rate-limit snapshot, plan, and last_synced_at" do
      account = @user.create_codex_account!(
        auth_mode: "chatgpt_browser",
        status: "connected",
        encrypted_credential_payload: "secret"
      )
      @client.respond(:get_auth_status, {
        "authMode" => "chatgpt_browser",
        "displayedEmail" => "fresh@example.com",
        "planType" => "team",
        "rateLimit" => { "primaryUsedPercent" => 12 },
        "expiresAt" => "2026-07-01T00:00:00Z"
      })

      result = service.refresh_status
      account.reload

      assert_equal "synced", result.state
      assert_equal "fresh@example.com", account.displayed_email
      assert_equal "team", account.plan_type
      assert_equal({ "primaryUsedPercent" => 12 }, account.rate_limit_snapshot)
      assert_equal Time.utc(2026, 7, 1, 0, 0, 0), account.credentials_expire_at.utc
      assert_equal @clock_time, account.last_synced_at.utc
    end

    test "refresh_status records failure metadata when client errors" do
      account = @user.create_codex_account!(
        auth_mode: "chatgpt_browser",
        status: "connected",
        encrypted_credential_payload: "secret"
      )
      @client = FakeClient.new(raises_on: { get_auth_status: AppServerClient::RpcError.new("server died") })

      assert_raises(AppServerClient::RpcError) { service.refresh_status }
      account.reload
      assert_equal "rpc_error", account.last_error_code
      assert_equal "server died", account.last_error_message
      assert_equal @clock_time, account.last_failed_at.utc
    end

    test "refresh_status returns absent when no codex account exists" do
      result = service.refresh_status
      assert_equal "absent", result.state
      assert_nil result.codex_account
    end

    test "refresh_status raises when account is not connected" do
      @user.create_codex_account!(
        auth_mode: "chatgpt_browser",
        status: "disconnected"
      )
      assert_raises(AccountConnections::InvalidAttempt) { service.refresh_status }
    end
  end
end
