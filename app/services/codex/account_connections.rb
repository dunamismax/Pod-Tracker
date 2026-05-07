module Codex
  # Orchestrates Codex App Server account-auth flows for a user. Wraps the
  # AppServerClient transport with database persistence so controllers can
  # start a login, surface the resulting URL or device code, poll for
  # completion, cancel, or disconnect without knowing JSON-RPC details.
  class AccountConnections
    BROWSER_AUTH_MODE = "chatgpt_browser".freeze
    DEVICE_CODE_AUTH_MODE = "chatgpt_device_code".freeze
    DEFAULT_CLIENT_LABEL = "ideal-magic".freeze

    Result = Struct.new(:attempt, :codex_account, :state, :detail, keyword_init: true)

    class Error < StandardError; end
    class InvalidAuthMode < Error; end
    class InvalidAttempt < Error; end

    class << self
      # Test override: a callable that returns a client. May accept zero
      # arguments (legacy fixture clients ignore which user is in flight) or
      # one argument (the user the connection is for). Production code does
      # not set this — it falls through to AppServerClient.for(user).
      attr_writer :client_factory
      attr_reader :client_factory

      def for(user, clock: -> { Time.current }, client_label: DEFAULT_CLIENT_LABEL)
        new(user, client: build_client_for(user), clock: clock, client_label: client_label)
      end

      def build_client_for(user)
        if @client_factory
          if @client_factory.respond_to?(:arity) && @client_factory.arity != 0
            @client_factory.call(user)
          else
            @client_factory.call
          end
        else
          AppServerClient.for(user)
        end
      end
    end

    def initialize(user, client: nil, clock: -> { Time.current }, client_label: DEFAULT_CLIENT_LABEL)
      @user = user
      @client = client || self.class.build_client_for(user)
      @clock = clock
      @client_label = client_label
    end

    # Start a fresh login attempt. Cancels any previously active attempt for the
    # same user so each user only has one in-flight login at a time.
    def start_login(auth_mode)
      raise InvalidAuthMode, "auth_mode must be #{BROWSER_AUTH_MODE} or #{DEVICE_CODE_AUTH_MODE}" unless valid_auth_mode?(auth_mode)
      cancel_active_attempts!

      attempt = @user.codex_login_attempts.create!(auth_mode: auth_mode, status: "pending", started_at: now)
      response = case auth_mode
      when BROWSER_AUTH_MODE
        @client.start_chatgpt_browser_login(client_label: @client_label)
      when DEVICE_CODE_AUTH_MODE
        @client.start_chatgpt_device_login(client_label: @client_label)
      end

      attempt.mark_awaiting_user!(
        handle: response.fetch("loginId"),
        login_url: response["loginUrl"],
        verification_uri: response["verificationUri"],
        user_code: response["userCode"],
        expires_at: parse_time(response["expiresAt"]),
        now: now
      )

      Result.new(attempt: attempt, codex_account: @user.codex_account, state: "awaiting_user", detail: response)
    rescue AppServerClient::Error => error
      attempt&.mark_failed!(code: rpc_failure_code(error), message: error.message, now: now)
      raise
    end

    # Poll the App Server for a previously started attempt. On completion,
    # persists the credential payload and account metadata.
    def poll_login(attempt)
      raise InvalidAttempt, "Login attempt is not active" unless attempt.active?
      attempt.touch_polled!(now: now)

      response = @client.poll_chatgpt_login(login_id: attempt.external_handle)
      state = response.fetch("state")

      case state
      when "awaiting_user"
        Result.new(attempt: attempt, codex_account: @user.codex_account, state: state, detail: response)
      when "completed"
        codex_account = persist_completed_login!(attempt, response)
        attempt.mark_completed!(now: now)
        Result.new(attempt: attempt, codex_account: codex_account, state: state, detail: response)
      when "cancelled"
        attempt.mark_cancelled!(now: now)
        Result.new(attempt: attempt, codex_account: @user.codex_account, state: state, detail: response)
      when "expired"
        attempt.mark_expired!(now: now)
        Result.new(attempt: attempt, codex_account: @user.codex_account, state: state, detail: response)
      when "failed"
        attempt.mark_failed!(
          code: response["failureCode"].presence || "codex_login_failed",
          message: response["failureMessage"].presence || "Codex App Server reported login failure",
          now: now
        )
        Result.new(attempt: attempt, codex_account: @user.codex_account, state: state, detail: response)
      else
        attempt.mark_failed!(code: "unknown_state", message: "Unknown login state: #{state.inspect}", now: now)
        raise Error, "Unknown Codex login state: #{state.inspect}"
      end
    rescue AppServerClient::Error => error
      attempt.mark_failed!(code: rpc_failure_code(error), message: error.message, now: now)
      raise
    end

    def cancel_login(attempt)
      raise InvalidAttempt, "Login attempt is not active" unless attempt.active?

      if attempt.external_handle.present?
        begin
          @client.cancel_chatgpt_login(login_id: attempt.external_handle)
        rescue AppServerClient::Error
          # The App Server may have already closed the login; continue with local cancel.
        end
      end

      attempt.mark_cancelled!(now: now)
      Result.new(attempt: attempt, codex_account: @user.codex_account, state: "cancelled", detail: {})
    end

    # Logs out at the Codex App Server (best-effort) and clears local
    # credentials by delegating to CodexAccount#disconnect!.
    def logout
      account = @user.codex_account
      return Result.new(attempt: nil, codex_account: nil, state: "absent", detail: {}) if account.nil?

      remote_detail = {}
      begin
        remote_detail = @client.logout_chatgpt
      rescue AppServerClient::Error
        # Disconnect locally even if the App Server is unreachable.
      end

      account.disconnect!(now: now)
      UserHome.purge!(@user)
      Result.new(attempt: nil, codex_account: account, state: "disconnected", detail: remote_detail)
    end

    # Reads fresh auth status from the App Server and refreshes the cached
    # rate-limit snapshot, plan type, and displayed email on the connected
    # account. Does nothing if the user has no connected account.
    def refresh_status
      account = @user.codex_account
      return Result.new(attempt: nil, codex_account: nil, state: "absent", detail: {}) if account.nil?
      raise InvalidAttempt, "Codex account is not connected" unless account.connected?

      unless UserHome.has_auth?(@user)
        account.disconnect!(now: now)
        return Result.new(attempt: nil, codex_account: account, state: "disconnected", detail: { "reason" => "missing_codex_home_auth" })
      end

      response = @client.get_auth_status
      attributes = {
        last_synced_at: now
      }
      attributes[:displayed_email] = response["displayedEmail"] if response.key?("displayedEmail")
      attributes[:plan_type] = response["planType"] if response.key?("planType")
      attributes[:rate_limit_snapshot] = response.fetch("rateLimit", {}) || {}
      attributes[:credentials_expire_at] = parse_time(response["expiresAt"]) if response.key?("expiresAt")

      account.update!(attributes)
      Result.new(attempt: nil, codex_account: account, state: "synced", detail: response)
    rescue AppServerClient::Error => error
      account.update!(last_failed_at: now, last_error_code: rpc_failure_code(error), last_error_message: error.message)
      raise
    end

    private

    def now
      @clock.call
    end

    def valid_auth_mode?(mode)
      [ BROWSER_AUTH_MODE, DEVICE_CODE_AUTH_MODE ].include?(mode)
    end

    def cancel_active_attempts!
      @user.codex_login_attempts.active.find_each do |stale|
        next if stale.external_handle.blank?
        begin
          @client.cancel_chatgpt_login(login_id: stale.external_handle)
        rescue AppServerClient::Error
          # Best-effort cancel.
        end
      ensure
        stale.mark_cancelled!(now: now)
      end
    end

    def persist_completed_login!(attempt, response)
      account = @user.codex_account || @user.build_codex_account
      account.assign_attributes(
        auth_mode: attempt.auth_mode,
        status: "connected",
        encrypted_credential_payload: response.fetch("credential"),
        credential_metadata: response["credentialMetadata"] || {},
        rate_limit_snapshot: response["rateLimit"] || {},
        displayed_email: response["displayedEmail"],
        plan_type: response["planType"],
        credentials_expire_at: parse_time(response["expiresAt"]),
        connected_at: now,
        last_synced_at: now,
        last_error_code: nil,
        last_error_message: nil,
        disconnected_at: nil
      )
      account.save!
      account
    end

    def rpc_failure_code(error)
      case error
      when AppServerClient::TransportError then "transport_error"
      when AppServerClient::RpcError then "rpc_error"
      when AppServerClient::NotConnectedError then "not_connected"
      else "codex_error"
      end
    end

    def parse_time(value)
      return nil if value.blank?
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
