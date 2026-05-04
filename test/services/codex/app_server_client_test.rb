require "test_helper"

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
    end

    test "start_chatgpt_browser_login forwards to loginChatGpt with protocolVersion" do
      transport = FakeTransport.new(scripted: {
        "loginChatGpt" => { "loginId" => "abc", "loginUrl" => "https://chatgpt.com/login/abc" }
      })
      client = AppServerClient.new(transport: transport)
      result = client.start_chatgpt_browser_login(client_label: "ideal-magic")

      assert_equal "abc", result["loginId"]
      assert_equal "https://chatgpt.com/login/abc", result["loginUrl"]
      method, params = transport.calls.first
      assert_equal "loginChatGpt", method
      assert_equal "1", params["protocolVersion"]
      assert_equal "ideal-magic", params["clientLabel"]
    end

    test "start_chatgpt_device_login uses loginChatGptDeviceCode" do
      transport = FakeTransport.new(scripted: {
        "loginChatGptDeviceCode" => {
          "loginId" => "dev-1",
          "userCode" => "WXYZ-1234",
          "verificationUri" => "https://chatgpt.com/device"
        }
      })
      client = AppServerClient.new(transport: transport)
      result = client.start_chatgpt_device_login

      assert_equal "WXYZ-1234", result["userCode"]
      assert_equal "loginChatGptDeviceCode", transport.calls.first.first
    end

    test "poll_chatgpt_login passes loginId" do
      transport = FakeTransport.new(scripted: {
        "getLoginChatGptStatus" => { "state" => "awaiting_user" }
      })
      client = AppServerClient.new(transport: transport)
      client.poll_chatgpt_login(login_id: "abc")
      _, params = transport.calls.first
      assert_equal "abc", params["loginId"]
    end

    test "cancel_chatgpt_login passes loginId" do
      transport = FakeTransport.new(scripted: {
        "cancelLoginChatGpt" => { "ok" => true }
      })
      client = AppServerClient.new(transport: transport)
      client.cancel_chatgpt_login(login_id: "abc")
      assert_equal "cancelLoginChatGpt", transport.calls.first.first
      assert_equal "abc", transport.calls.first.last["loginId"]
    end

    test "logout_chatgpt routes to logoutChatGpt" do
      transport = FakeTransport.new(scripted: { "logoutChatGpt" => {} })
      client = AppServerClient.new(transport: transport)
      client.logout_chatgpt
      assert_equal "logoutChatGpt", transport.calls.first.first
    end

    test "get_auth_status routes to getAuthStatus" do
      transport = FakeTransport.new(scripted: {
        "getAuthStatus" => { "authMode" => "chatgpt_browser", "displayedEmail" => "demo@example.com" }
      })
      client = AppServerClient.new(transport: transport)
      result = client.get_auth_status
      assert_equal "demo@example.com", result["displayedEmail"]
    end

    test "raises RpcError when transport returns a non-Hash result" do
      transport = FakeTransport.new(scripted: { "getAuthStatus" => "nope" })
      client = AppServerClient.new(transport: transport)
      assert_raises(AppServerClient::RpcError) { client.get_auth_status }
    end

    test "wraps unknown transport errors as TransportError" do
      transport = FakeTransport.new(
        scripted: { "loginChatGpt" => nil },
        raise_on: { "loginChatGpt" => RuntimeError.new("boom") }
      )
      client = AppServerClient.new(transport: transport)
      error = assert_raises(AppServerClient::TransportError) { client.start_chatgpt_browser_login }
      assert_match(/boom/, error.message)
    end

    test "preserves explicit RpcError raised by transport" do
      rpc = AppServerClient::RpcError.new("server says no", code: -32000)
      transport = FakeTransport.new(
        scripted: { "loginChatGpt" => nil },
        raise_on: { "loginChatGpt" => rpc }
      )
      client = AppServerClient.new(transport: transport)
      raised = assert_raises(AppServerClient::RpcError) { client.start_chatgpt_browser_login }
      assert_equal(-32000, raised.code)
    end

    test "default NullTransport raises TransportError so dev cannot accidentally call OpenAI" do
      client = AppServerClient.new
      assert_raises(AppServerClient::TransportError) { client.get_auth_status }
    end
  end
end
