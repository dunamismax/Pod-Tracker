require "json"
require "open3"
require "shellwords"
require "timeout"

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
    JSONRPC_METHODS = {
      start_login:      "account/login/start",
      cancel_login:     "account/login/cancel",
      logout:           "account/logout",
      read_account:     "account/read",
      read_rate_limits: "account/rateLimits/read"
    }.freeze

    CLIENT_INFO = {
      "name" => "ideal_magic",
      "title" => "Ideal Magic",
      "version" => "0.1.0"
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

    class StdioTransport
      def initialize(command:, request_timeout: 20, client_info: CLIENT_INFO)
        @command = command
        @request_timeout = request_timeout.to_f
        @client_info = client_info
        @mutex = Mutex.new
        @next_id = 0
        @initialized = false
        @stderr_tail = []
      end

      def request(method, params = {})
        @mutex.synchronize do
          with_timeout(method) do
            start_process!
            initialize_connection! unless @initialized
            send_request(method, params)
          end
        end
      end

      private

      def with_timeout(method, &block)
        Timeout.timeout(@request_timeout, &block)
      rescue Timeout::Error
        stop_process
        raise TransportError, "Codex App Server timed out during #{method}."
      end

      def start_process!
        return if @stdin && @stdout && @wait_thread&.alive?

        argv = @command.is_a?(Array) ? @command : Shellwords.split(@command.to_s)
        raise TransportError, "CODEX_APP_SERVER_COMMAND is blank." if argv.empty?

        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*argv)
        @initialized = false
        start_stderr_reader
      rescue Errno::ENOENT => e
        raise TransportError, "Could not start Codex App Server command #{argv.inspect}: #{e.message}"
      end

      def initialize_connection!
        id = next_id
        write_message(
          "method" => "initialize",
          "id" => id,
          "params" => { "clientInfo" => @client_info }
        )
        read_response(id, "initialize")
        write_message("method" => "initialized", "params" => {})
        @initialized = true
      end

      def send_request(method, params)
        id = next_id
        write_message("method" => method, "id" => id, "params" => params)
        read_response(id, method)
      end

      def read_response(expected_id, method)
        loop do
          line = @stdout.gets
          unless line
            stop_process
            raise TransportError, "Codex App Server closed stdout during #{method}.#{stderr_context}"
          end

          message = JSON.parse(line)
          next unless message["id"] == expected_id

          if (error = message["error"])
            raise RpcError.new(error["message"].presence || "Codex App Server RPC error.", code: error["code"], data: error["data"])
          end

          return message.fetch("result", {})
        end
      rescue JSON::ParserError => e
        raise TransportError, "Codex App Server returned invalid JSON during #{method}: #{e.message}"
      end

      def write_message(message)
        @stdin.write("#{JSON.generate(message)}\n")
        @stdin.flush
      rescue IOError, Errno::EPIPE => e
        stop_process
        raise TransportError, "Could not write to Codex App Server: #{e.message}"
      end

      def next_id
        @next_id += 1
      end

      def start_stderr_reader
        Thread.new do
          @stderr.each_line do |line|
            @stderr_tail << line.strip
            @stderr_tail.shift while @stderr_tail.length > 10
          end
        rescue IOError
          nil
        end
      end

      def stop_process
        [ @stdin, @stdout, @stderr ].compact.each do |io|
          io.close unless io.closed?
        rescue IOError
          nil
        end
        if @wait_thread&.alive?
          Process.kill("TERM", @wait_thread.pid)
        end
      rescue Errno::ESRCH
        nil
      ensure
        @stdin = @stdout = @stderr = @wait_thread = nil
        @initialized = false
      end

      def stderr_context
        return "" if @stderr_tail.empty?
        " Last stderr: #{@stderr_tail.join(' | ')}"
      end
    end

    # Default transport that fails fast. Real environments must inject a
    # transport bound to a running Codex App Server; this stub keeps tests and
    # development from accidentally pretending to call OpenAI.
    class NullTransport
      def request(method, _params = {})
        raise TransportError, "Codex App Server transport is not configured (attempted #{method})."
      end
    end

    def self.from_environment(env: ENV)
      enabled = ActiveModel::Type::Boolean.new.cast(env["CODEX_APP_SERVER_ENABLED"])
      return new unless enabled

      command = env["CODEX_APP_SERVER_COMMAND"].presence || "codex app-server"
      timeout = env.fetch("CODEX_APP_SERVER_REQUEST_TIMEOUT_SECONDS", 20).to_i
      new(transport: StdioTransport.new(command: command, request_timeout: timeout))
    end

    def initialize(transport: NullTransport.new)
      @transport = transport
    end

    # Begin a browser-OAuth ChatGPT login. Returns a hash with at minimum
    #   "loginId"   - opaque handle owned by the App Server
    #   "loginUrl"  - URL the user opens in a browser
    #   "expiresAt" - ISO-8601 expiration, optional
    def start_chatgpt_browser_login(client_label: nil)
      normalize_browser_login(call(:start_login, compact("type" => "chatgpt", "serviceName" => client_label)))
    end

    # Begin a device-code ChatGPT login. Returns a hash with at minimum
    #   "loginId"          - opaque handle owned by the App Server
    #   "userCode"         - short code displayed to the user
    #   "verificationUri"  - URL the user opens to enter the code
    #   "expiresAt"        - ISO-8601 expiration, optional
    def start_chatgpt_device_login(client_label: nil)
      normalize_device_login(call(:start_login, compact("type" => "chatgptDeviceCode", "serviceName" => client_label)))
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
      status = get_auth_status(refresh_token: true)
      return { "state" => "awaiting_user", "loginId" => login_id } unless status["authMode"].present?

      status.merge(
        "state" => "completed",
        "loginId" => login_id,
        "credential" => JSON.generate(
          "storage" => "codex_app_server",
          "authMode" => status["authMode"],
          "connectedAt" => Time.current.utc.iso8601
        ),
        "credentialMetadata" => compact(
          "storage" => "codex_app_server",
          "accountType" => status["accountType"],
          "requiresOpenaiAuth" => status["requiresOpenaiAuth"]
        )
      )
    end

    def cancel_chatgpt_login(login_id:)
      call(:cancel_login, "loginId" => login_id)
    end

    def logout_chatgpt(account_id: nil)
      call(:logout, compact("accountId" => account_id))
    end

    # Returns auth status. When connected, includes:
    #   "authMode", "displayedEmail", "planType", "rateLimit", "expiresAt".
    def get_auth_status(account_id: nil, refresh_token: false)
      account_result = call(:read_account, compact("accountId" => account_id, "refreshToken" => refresh_token))
      rate_limit_result = call(:read_rate_limits, {})
      normalize_auth_status(account_result, rate_limit_result)
    end

    private

    def call(operation, params = {})
      method = JSONRPC_METHODS.fetch(operation)
      result = @transport.request(method, params)
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

    def normalize_browser_login(result)
      {
        "loginId" => result.fetch("loginId"),
        "loginUrl" => result["authUrl"],
        "expiresAt" => result["expiresAt"]
      }.compact
    end

    def normalize_device_login(result)
      {
        "loginId" => result.fetch("loginId"),
        "userCode" => result["userCode"],
        "verificationUri" => result["verificationUrl"],
        "expiresAt" => result["expiresAt"]
      }.compact
    end

    def normalize_auth_status(account_result, rate_limit_result)
      account = account_result["account"]
      return {
        "authMode" => nil,
        "requiresOpenaiAuth" => account_result["requiresOpenaiAuth"],
        "rateLimit" => normalized_rate_limit(rate_limit_result)
      } unless account.is_a?(Hash)

      {
        "authMode" => normalize_auth_mode(account["type"]),
        "accountType" => account["type"],
        "displayedEmail" => account["email"],
        "planType" => account["planType"],
        "requiresOpenaiAuth" => account_result["requiresOpenaiAuth"],
        "rateLimit" => normalized_rate_limit(rate_limit_result)
      }.compact
    end

    def normalize_auth_mode(type)
      case type
      when "chatgpt" then AccountConnections::BROWSER_AUTH_MODE
      when "chatgptAuthTokens" then AccountConnections::BROWSER_AUTH_MODE
      when "apiKey" then "api_key"
      else type
      end
    end

    def normalized_rate_limit(result)
      return {} unless result.is_a?(Hash)
      result["rateLimitsByLimitId"].presence || result["rateLimits"].presence || {}
    end
  end
end
