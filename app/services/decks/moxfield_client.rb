require "json"
require "net/http"
require "uri"

module Decks
  class MoxfieldClient
    API_HOST = "api2.moxfield.com".freeze
    USER_AGENT = "IdealMagic/0.1 (+https://ideal-magic.com; github.com/dunamismax/ideal-magic)".freeze
    ACCEPT_HEADER = "application/json".freeze
    OPEN_TIMEOUT_SECONDS = 5
    READ_TIMEOUT_SECONDS = 15

    class Error < StandardError; end
    class NotFoundError < Error; end
    class RateLimitedError < Error; end
    class TransportError < Error; end

    def initialize(http_adapter: Net::HTTP)
      @http_adapter = http_adapter
    end

    def fetch_deck(slug)
      uri = URI("https://#{API_HOST}/v3/decks/all/#{slug}")
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = ACCEPT_HEADER

      response = @http_adapter.start(
        uri.host, uri.port,
        use_ssl: true,
        open_timeout: OPEN_TIMEOUT_SECONDS,
        read_timeout: READ_TIMEOUT_SECONDS
      ) { |http| http.request(request) }

      handle_response(response)
    rescue SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      raise TransportError, "Could not reach Moxfield: #{e.message}"
    end

    private

    def handle_response(response)
      case response.code.to_i
      when 200
        JSON.parse(response.body)
      when 404
        raise NotFoundError, "Moxfield deck not found"
      when 429
        raise RateLimitedError, "Moxfield rate-limited the request"
      else
        raise Error, "Moxfield request failed: HTTP #{response.code}"
      end
    rescue JSON::ParserError => e
      raise Error, "Moxfield returned malformed JSON: #{e.message}"
    end
  end
end
