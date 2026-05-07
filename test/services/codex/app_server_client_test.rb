require "test_helper"
require "rbconfig"
require "tempfile"

module Codex
  class AppServerClientTest < ActiveSupport::TestCase
    class FakeTransport
      attr_reader :calls

      def initialize(scripted: {}, raise_on: nil)
        @scripted = scripted
        @raise_on = raise_on
        @calls = []
      end

      def request(method, params = {})
        @calls << [ method, params ]
        if @raise_on && @raise_on[method]
          raise @raise_on[method]
        end
        @scripted.fetch(method) do
          raise "Unexpected JSON-RPC call: #{method}"
        end
      end

      def request_and_stream(method, params = {}, until_method:)
        @calls << [ method, params.merge("untilMethod" => until_method) ]
        Array(@scripted.fetch("#{method}:notifications", [])).each { |message| yield message }
        @scripted.fetch(method) do
          raise "Unexpected streaming JSON-RPC call: #{method}"
        end
      end
    end

    test "start_chatgpt_browser_login forwards to documented account login method" do
      transport = FakeTransport.new(scripted: {
        "account/login/start" => { "loginId" => "abc", "authUrl" => "https://chatgpt.com/login/abc" }
      })
      client = AppServerClient.new(transport: transport)
      result = client.start_chatgpt_browser_login(client_label: "ideal-magic")

      assert_equal "abc", result["loginId"]
      assert_equal "https://chatgpt.com/login/abc", result["loginUrl"]
      method, params = transport.calls.first
      assert_equal "account/login/start", method
      assert_equal "chatgpt", params["type"]
      assert_equal "ideal-magic", params["serviceName"]
    end

    test "start_chatgpt_device_login uses documented device-code login type" do
      transport = FakeTransport.new(scripted: {
        "account/login/start" => {
          "loginId" => "dev-1",
          "userCode" => "WXYZ-1234",
          "verificationUrl" => "https://auth.openai.com/codex/device"
        }
      })
      client = AppServerClient.new(transport: transport)
      result = client.start_chatgpt_device_login

      assert_equal "WXYZ-1234", result["userCode"]
      assert_equal "https://auth.openai.com/codex/device", result["verificationUri"]
      assert_equal "account/login/start", transport.calls.first.first
      assert_equal "chatgptDeviceCode", transport.calls.first.last["type"]
    end

    test "poll_chatgpt_login returns awaiting_user while account is not connected" do
      transport = FakeTransport.new(scripted: {
        "account/read" => { "account" => nil, "requiresOpenaiAuth" => true }
      })
      client = AppServerClient.new(transport: transport)
      result = client.poll_chatgpt_login(login_id: "abc")

      assert_equal "awaiting_user", result["state"]
      assert_equal "abc", result["loginId"]
      assert_equal true, transport.calls.first.last["refreshToken"]
      assert_equal [ "account/read" ], transport.calls.map(&:first)
    end

    test "poll_chatgpt_login does not read rate limits before authentication" do
      transport = FakeTransport.new(
        scripted: {
          "account/read" => { "account" => nil, "requiresOpenaiAuth" => true }
        },
        raise_on: {
          "account/rateLimits/read" => AppServerClient::RpcError.new("codex account authentication required to read rate limits")
        }
      )
      client = AppServerClient.new(transport: transport)
      result = client.poll_chatgpt_login(login_id: "abc")

      assert_equal "awaiting_user", result["state"]
      assert_equal [ "account/read" ], transport.calls.map(&:first)
    end

    test "poll_chatgpt_login normalizes connected account metadata" do
      transport = FakeTransport.new(scripted: {
        "account/read" => {
          "account" => { "type" => "chatgpt", "email" => "demo@example.com", "planType" => "plus" },
          "requiresOpenaiAuth" => true
        },
        "account/rateLimits/read" => {
          "rateLimits" => { "limitId" => "codex", "primary" => { "usedPercent" => 10 } }
        }
      })
      client = AppServerClient.new(transport: transport)
      result = client.poll_chatgpt_login(login_id: "abc")

      assert_equal "completed", result["state"]
      assert_equal "chatgpt_browser", result["authMode"]
      assert_equal "demo@example.com", result["displayedEmail"]
      assert_equal "plus", result["planType"]
      assert_equal "codex_app_server", JSON.parse(result["credential"])["storage"]
    end

    test "cancel_chatgpt_login passes loginId" do
      transport = FakeTransport.new(scripted: {
        "account/login/cancel" => {}
      })
      client = AppServerClient.new(transport: transport)
      client.cancel_chatgpt_login(login_id: "abc")
      assert_equal "account/login/cancel", transport.calls.first.first
      assert_equal "abc", transport.calls.first.last["loginId"]
    end

    test "logout_chatgpt routes to account logout" do
      transport = FakeTransport.new(scripted: { "account/logout" => {} })
      client = AppServerClient.new(transport: transport)
      client.logout_chatgpt
      assert_equal "account/logout", transport.calls.first.first
    end

    test "get_auth_status normalizes account read and rate limit responses" do
      transport = FakeTransport.new(scripted: {
        "account/read" => {
          "account" => { "type" => "chatgpt", "email" => "demo@example.com", "planType" => "team" },
          "requiresOpenaiAuth" => true
        },
        "account/rateLimits/read" => {
          "rateLimitsByLimitId" => {
            "codex" => { "limitId" => "codex", "primary" => { "usedPercent" => 5 } }
          }
        }
      })
      client = AppServerClient.new(transport: transport)
      result = client.get_auth_status
      assert_equal "demo@example.com", result["displayedEmail"]
      assert_equal "team", result["planType"]
      assert_equal({ "codex" => { "limitId" => "codex", "primary" => { "usedPercent" => 5 } } }, result["rateLimit"])
    end

    test "evaluate_scorecard starts a thread and captures the completed agent JSON" do
      transport = FakeTransport.new(scripted: {
        "thread/start" => { "thread" => { "id" => "thread-1" } },
        "turn/start" => { "id" => "turn-1", "status" => "running" },
        "turn/start:notifications" => [
          {
            "method" => "item/completed",
            "params" => {
              "item" => {
                "type" => "agentMessage",
                "text" => "{ \"schema_version\": \"ai-scorecard-v1\", \"summary\": \"ok\" }",
                "phase" => "final_answer"
              }
            }
          },
          { "method" => "turn/completed", "params" => { "turnId" => "turn-1", "status" => "completed" } }
        ],
        "thread/unsubscribe" => {}
      })
      client = AppServerClient.new(transport: transport)
      result = client.evaluate_scorecard(
        {
          "messages" => [
            { "role" => "system", "content" => "Return JSON." },
            { "role" => "user", "content" => "{}" }
          ]
        },
        model: "gpt-test"
      )

      assert_equal "thread/start", transport.calls[0].first
      assert_equal "turn/start", transport.calls[1].first
      assert_equal "thread-1", transport.calls[1].last["threadId"]
      assert_equal "turn/completed", transport.calls[1].last["untilMethod"]
      assert_equal "gpt-test", transport.calls[1].last.dig("settings", "model")
      assert_match(/SYSTEM:/, transport.calls[1].last.dig("input", 0, "text"))
      assert_equal "{ \"schema_version\": \"ai-scorecard-v1\", \"summary\": \"ok\" }", result["text"]
      assert_equal "thread/unsubscribe", transport.calls.last.first
    end

    test "raises RpcError when transport returns a non-Hash result" do
      transport = FakeTransport.new(scripted: { "account/read" => "nope" })
      client = AppServerClient.new(transport: transport)
      assert_raises(AppServerClient::RpcError) { client.get_auth_status }
    end

    test "wraps unknown transport errors as TransportError" do
      transport = FakeTransport.new(
        scripted: { "account/login/start" => nil },
        raise_on: { "account/login/start" => RuntimeError.new("boom") }
      )
      client = AppServerClient.new(transport: transport)
      error = assert_raises(AppServerClient::TransportError) { client.start_chatgpt_browser_login }
      assert_match(/boom/, error.message)
    end

    test "preserves explicit RpcError raised by transport" do
      rpc = AppServerClient::RpcError.new("server says no", code: -32000)
      transport = FakeTransport.new(
        scripted: { "account/login/start" => nil },
        raise_on: { "account/login/start" => rpc }
      )
      client = AppServerClient.new(transport: transport)
      raised = assert_raises(AppServerClient::RpcError) { client.start_chatgpt_browser_login }
      assert_equal(-32000, raised.code)
    end

    test "default NullTransport raises TransportError so dev cannot accidentally call OpenAI" do
      client = AppServerClient.new
      assert_raises(AppServerClient::TransportError) { client.get_auth_status }
    end

    test "from_environment keeps NullTransport unless feature flag is enabled" do
      client = AppServerClient.from_environment(env: {})
      assert_raises(AppServerClient::TransportError) { client.get_auth_status }
    end

    test "stdio transport spawns the child process with the supplied env hash" do
      script = Tempfile.new([ "fake-codex-app-server", ".rb" ])
      script.write(<<~RUBY)
        require "json"

        initialize_request = JSON.parse(STDIN.gets)
        puts JSON.generate("id" => initialize_request.fetch("id"), "result" => { "ok" => true })
        STDOUT.flush

        initialized = JSON.parse(STDIN.gets)
        raise "expected initialized notification" unless initialized["method"] == "initialized"

        request = JSON.parse(STDIN.gets)
        puts JSON.generate("id" => request.fetch("id"), "result" => {
          "codex_home" => ENV["CODEX_HOME"],
          "path_present" => !ENV["PATH"].to_s.empty?,
          "secret_leaked" => ENV["RAILS_SECRET"]
        })
        STDOUT.flush
      RUBY
      script.close

      transport = AppServerClient::StdioTransport.new(
        command: [ RbConfig.ruby, script.path ],
        request_timeout: 2,
        env: { "CODEX_HOME" => "/tmp/codex-user-99", "PATH" => ENV["PATH"] }
      )
      result = transport.request("account/read", {})

      assert_equal "/tmp/codex-user-99", result["codex_home"]
      assert_equal true, result["path_present"]
      assert_nil result["secret_leaked"]
    ensure
      script&.unlink
    end

    test "for(user) builds a client whose stdio transport carries the user's CODEX_HOME" do
      user = users(:one)
      tmp_root = Pathname.new(Dir.mktmpdir("codex-home-for-test-"))
      UserHome.root_path_override = tmp_root
      env = {
        "CODEX_APP_SERVER_ENABLED" => "true",
        "CODEX_APP_SERVER_COMMAND" => "/bin/true",
        "PATH" => ENV["PATH"]
      }
      client = AppServerClient.for(user, env: env)
      transport = client.instance_variable_get(:@transport)
      transport_env = transport.instance_variable_get(:@env)

      expected_home = tmp_root.join(user.id.to_s).to_s
      assert_equal expected_home, transport_env["CODEX_HOME"]
      assert File.directory?(expected_home), "expected user codex home to be created"
      mode = File.stat(expected_home).mode & 0o777
      assert_equal 0o700, mode
    ensure
      UserHome.reset_root_override!
      FileUtils.remove_entry(tmp_root) if tmp_root&.exist?
    end

    test "build_transport_env only forwards an allowlist of parent env keys" do
      env = AppServerClient.build_transport_env(
        env: {
          "PATH" => "/usr/bin",
          "HOME" => "/home/sawyer",
          "RAILS_SECRET_KEY_BASE" => "do-not-leak",
          "IDEAL_MAGIC_DATABASE_PASSWORD" => "do-not-leak"
        },
        codex_home: "/var/lib/ideal-magic/codex/42"
      )

      assert_equal "/var/lib/ideal-magic/codex/42", env["CODEX_HOME"]
      assert_equal "/usr/bin", env["PATH"]
      assert_equal "/home/sawyer", env["HOME"]
      refute env.key?("RAILS_SECRET_KEY_BASE"), "must not forward Rails secrets"
      refute env.key?("IDEAL_MAGIC_DATABASE_PASSWORD"), "must not forward DB password"
    end

    test "stdio transport initializes the app server protocol before requests" do
      script = Tempfile.new([ "fake-codex-app-server", ".rb" ])
      script.write(<<~RUBY)
        require "json"

        initialize_request = JSON.parse(STDIN.gets)
        puts JSON.generate("id" => initialize_request.fetch("id"), "result" => { "server" => "ready" })
        STDOUT.flush

        initialized = JSON.parse(STDIN.gets)
        raise "expected initialized notification" unless initialized["method"] == "initialized"

        request = JSON.parse(STDIN.gets)
        puts JSON.generate("id" => request.fetch("id"), "result" => {
          "method" => request.fetch("method"),
          "params" => request.fetch("params")
        })
        STDOUT.flush
      RUBY
      script.close

      transport = AppServerClient::StdioTransport.new(
        command: [ RbConfig.ruby, script.path ],
        request_timeout: 2
      )
      result = transport.request("account/read", "refreshToken" => true)

      assert_equal "account/read", result["method"]
      assert_equal true, result["params"]["refreshToken"]
    ensure
      script&.unlink
    end
  end
end
