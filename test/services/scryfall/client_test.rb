require "test_helper"

module Scryfall
  class ClientTest < ActiveSupport::TestCase
    test "bulk data index uses polite Scryfall headers over HTTPS" do
      adapter = FakeHttpAdapter.new(
        FakeResponse.new("200", { "data" => [ { "type" => "default_cards" } ] }.to_json)
      )
      client = Client.new(http_adapter: adapter)

      assert_equal([ { "type" => "default_cards" } ], client.bulk_data_index)
      assert_equal({ host: "api.scryfall.com", port: 443, use_ssl: true }, adapter.starts.first)
      assert_equal(Client::USER_AGENT, adapter.requests.first["User-Agent"])
      assert_equal(Client::ACCEPT_HEADER, adapter.requests.first["Accept"])
    end

    test "bulk data object raises for missing type" do
      adapter = FakeHttpAdapter.new(FakeResponse.new("200", { "data" => [] }.to_json))
      client = Client.new(http_adapter: adapter)

      error = assert_raises(Client::Error) { client.bulk_data_object("missing") }

      assert_match(/not found/, error.message)
    end

    test "rate limited responses expose retry after value without retrying" do
      adapter = FakeHttpAdapter.new(FakeResponse.new("429", "", { "Retry-After" => "2" }))
      client = Client.new(http_adapter: adapter)

      error = assert_raises(Client::RateLimitedError) { client.bulk_data_index }

      assert_equal("2", error.retry_after)
      assert_equal(1, adapter.requests.size)
    end

    FakeResponse = Struct.new(:code, :body, :headers) do
      def initialize(code, body, headers = {})
        super(code, body, headers)
      end

      def [](header)
        headers[header]
      end

      def is_a?(klass)
        klass == Net::HTTPSuccess && code.start_with?("2") || super
      end
    end

    class FakeHttpAdapter
      attr_reader :requests, :starts

      def initialize(response)
        @response = response
        @requests = []
        @starts = []
      end

      def start(host, port, use_ssl:)
        @starts << { host: host, port: port, use_ssl: use_ssl }
        yield FakeHttp.new(self, @response)
      end

      def record(request)
        @requests << request
      end
    end

    class FakeHttp
      def initialize(adapter, response)
        @adapter = adapter
        @response = response
      end

      def request(request)
        @adapter.record(request)
        @response
      end
    end
  end
end
