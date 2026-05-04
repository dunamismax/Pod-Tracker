require "test_helper"

module Decks
  class MoxfieldClientTest < ActiveSupport::TestCase
    FakeResponse = Struct.new(:code, :body)

    class FakeHttp
      def initialize(response)
        @response = response
        @started = nil
      end

      def start(host, port, **opts, &block)
        @started = { host: host, port: port, options: opts }
        block.call(self)
      end

      def request(_request)
        @response
      end

      attr_reader :started
    end

    def fake_response(code, body)
      FakeResponse.new(code.to_s, body)
    end

    test "fetch_deck returns parsed JSON on 200" do
      response = fake_response(200, '{"name":"x"}')
      client = MoxfieldClient.new(http_adapter: FakeHttp.new(response))
      assert_equal "x", client.fetch_deck("abc")["name"]
    end

    test "fetch_deck raises NotFoundError on 404" do
      response = fake_response(404, "")
      client = MoxfieldClient.new(http_adapter: FakeHttp.new(response))
      assert_raises(MoxfieldClient::NotFoundError) { client.fetch_deck("abc") }
    end

    test "fetch_deck raises RateLimitedError on 429" do
      response = fake_response(429, "")
      client = MoxfieldClient.new(http_adapter: FakeHttp.new(response))
      assert_raises(MoxfieldClient::RateLimitedError) { client.fetch_deck("abc") }
    end

    test "fetch_deck raises Error on other non-success codes" do
      response = fake_response(500, "")
      client = MoxfieldClient.new(http_adapter: FakeHttp.new(response))
      assert_raises(MoxfieldClient::Error) { client.fetch_deck("abc") }
    end

    test "fetch_deck raises Error on malformed JSON" do
      response = fake_response(200, "{not json")
      client = MoxfieldClient.new(http_adapter: FakeHttp.new(response))
      assert_raises(MoxfieldClient::Error) { client.fetch_deck("abc") }
    end

    test "fetch_deck raises TransportError on socket failures" do
      blowing_adapter = Class.new do
        def self.start(*) = raise SocketError, "name resolution failed"
      end
      client = MoxfieldClient.new(http_adapter: blowing_adapter)
      assert_raises(MoxfieldClient::TransportError) { client.fetch_deck("abc") }
    end
  end
end
