require "json"
require "net/http"

module Scryfall
  class Client
    API_BASE_URI = URI("https://api.scryfall.com")
    ACCEPT_HEADER = "application/json;q=0.9,*/*;q=0.8"
    MINIMUM_API_INTERVAL = 0.11
    USER_AGENT = "IdealMagic/0.1 (+https://ideal-magic.com; github.com/dunamismax/ideal-magic)"

    class Error < StandardError; end
    class RateLimitedError < Error
      attr_reader :retry_after

      def initialize(message, retry_after:)
        super(message)
        @retry_after = retry_after
      end
    end

    def initialize(http_adapter: Net::HTTP, sleeper: ->(seconds) { sleep(seconds) },
      time_source: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @http_adapter = http_adapter
      @sleeper = sleeper
      @time_source = time_source
      @last_api_request_at = nil
      @rate_limit_mutex = Mutex.new
    end

    def bulk_data_index
      response = request(API_BASE_URI + "/bulk-data", throttle: true)
      JSON.parse(response.body).fetch("data")
    end

    def bulk_data_object(type)
      bulk_data_index.find { |entry| entry.fetch("type") == type.to_s } ||
        raise(Error, "Scryfall bulk data type not found: #{type}")
    end

    def each_bulk_object(download_uri)
      return enum_for(:each_bulk_object, download_uri) unless block_given?

      stream_request(URI(download_uri)) do |chunks|
        JsonArrayStream.new(chunks).each { |object| yield object }
      end
    end

    private

    def request(uri, throttle:)
      throttle_api_request! if throttle && uri.host == API_BASE_URI.host

      http_request = Net::HTTP::Get.new(uri)
      apply_headers(http_request)

      response = @http_adapter.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(http_request)
      end

      handle_response(response, uri)
    end

    def stream_request(uri)
      http_request = Net::HTTP::Get.new(uri)
      apply_headers(http_request)

      @http_adapter.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(http_request) do |response|
          handle_response(response, uri)
          yield response.enum_for(:read_body)
        end
      end
    end

    def apply_headers(request)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = ACCEPT_HEADER
    end

    def handle_response(response, uri)
      if response.code.to_i == 429
        raise RateLimitedError.new(
          "Scryfall rate limit reached for #{uri}",
          retry_after: response["Retry-After"]
        )
      end

      return response if response.is_a?(Net::HTTPSuccess)

      raise Error, "Scryfall request failed for #{uri}: HTTP #{response.code}"
    end

    def throttle_api_request!
      @rate_limit_mutex.synchronize do
        now = @time_source.call
        elapsed = @last_api_request_at ? now - @last_api_request_at : MINIMUM_API_INTERVAL
        @sleeper.call(MINIMUM_API_INTERVAL - elapsed) if elapsed < MINIMUM_API_INTERVAL
        @last_api_request_at = @time_source.call
      end
    end
  end
end
