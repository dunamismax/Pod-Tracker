module Codex
  # Boundary in front of OpenAI's documented Codex App Server JSON-RPC surface.
  #
  # The Codex App Server is responsible for the actual ChatGPT browser-OAuth and
  # device-code login flows. Ideal Magic never sees the user's ChatGPT password;
  # it asks the App Server to start a login, surfaces the resulting URL or user
  # code, and waits for the App Server to confirm the credentials.
  #
  # The transport is intentionally pluggable so the service layer and controllers
  # can be exercised in tests without spawning a real Codex App Server. A
  # transport must respond to:
  #
  #     transport.request(method, params = {})
  #
  # returning a Hash with String keys (the JSON-RPC `result` payload) or raising
  # AppServerClient::TransportError / AppServerClient::RpcError for failures.
  class AppServerClient
    DEFAULT_PROTOCOL_VERSION = "1"

    JSONRPC_METHODS = {
      start_chatgpt_browser_login: "loginChatGpt",
      cancel_chatgpt_login:        "cancelLoginChatGpt",
      start_chatgpt_device_login:  "loginChatGptDeviceCode",
      poll_chatgpt_login:          "getLoginChatGptStatus",
      logout_chatgpt:              "logoutChatGpt",
      get_auth_status:             "getAuthStatus"
    }.freeze

    class Error < StandardError; end
    class TransportError < Error; end
    class RpcError < Error
      attr_reader :code, :data

      def initialize(message, code: nil, data: nil)
        super(message)
        @code = code
        @data = data
      end
    end
    class NotConnectedError < Error; end

    # Default transport that fails fast. Real environments must inject a
    # transport bound to a running Codex App Server; this stub keeps tests and
    # development from accidentally pretending to call OpenAI.
    class NullTransport
      def request(method, _params = {})
        raise TransportError, "Codex App Server transport is not configured (attempted #{method})."
      end
    end

    def initialize(transport: NullTransport.new, protocol_version: DEFAULT_PROTOCOL_VERSION)
      @transport = transport
      @protocol_version = protocol_version
    end

    # Begin a browser-OAuth ChatGPT login. Returns a hash with at minimum
    #   "loginId"   - opaque handle owned by the App Server
    #   "loginUrl"  - URL the user opens in a browser
    #   "expiresAt" - ISO-8601 expiration, optional
    def start_chatgpt_browser_login(client_label: nil)
      call(:start_chatgpt_browser_login, compact("clientLabel" => client_label))
    end

    # Begin a device-code ChatGPT login. Returns a hash with at minimum
    #   "loginId"          - opaque handle owned by the App Server
    #   "userCode"         - short code displayed to the user
    #   "verificationUri"  - URL the user opens to enter the code
    #   "expiresAt"        - ISO-8601 expiration, optional
    def start_chatgpt_device_login(client_label: nil)
      call(:start_chatgpt_device_login, compact("clientLabel" => client_label))
    end

    # Poll a pending login. Returns a hash:
    #   "state" => "awaiting_user"|"completed"|"cancelled"|"expired"|"failed"
    # When state == "completed" the response also includes:
    #   "credential"      - opaque credential payload to persist (encrypted)
    #   "displayedEmail"  - ChatGPT account email if returned
    #   "planType"        - ChatGPT plan label if returned
    #   "rateLimit"       - rate-limit snapshot if returned
    #   "credentialMetadata" - non-sensitive metadata about the credential
    #   "expiresAt"       - credential expiration if returned
    def poll_chatgpt_login(login_id:)
      call(:poll_chatgpt_login, "loginId" => login_id)
    end

    def cancel_chatgpt_login(login_id:)
      call(:cancel_chatgpt_login, "loginId" => login_id)
    end

    def logout_chatgpt(account_id: nil)
      call(:logout_chatgpt, compact("accountId" => account_id))
    end

    # Returns auth status. When connected, includes:
    #   "authMode", "displayedEmail", "planType", "rateLimit", "expiresAt".
    def get_auth_status(account_id: nil)
      call(:get_auth_status, compact("accountId" => account_id))
    end

    private

    def call(operation, params = {})
      method = JSONRPC_METHODS.fetch(operation)
      payload = { "protocolVersion" => @protocol_version }.merge(params)
      result = @transport.request(method, payload)
      raise RpcError, "Codex App Server returned a non-Hash result for #{method}" unless result.is_a?(Hash)
      result
    rescue TransportError, RpcError, NotConnectedError
      raise
    rescue StandardError => e
      raise TransportError, "Codex App Server transport error for #{operation}: #{e.class}: #{e.message}"
    end

    def compact(hash)
      hash.reject { |_, value| value.nil? }
    end
  end
end
