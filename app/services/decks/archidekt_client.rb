require "json"
require "net/http"
require "uri"

module Decks
  class ArchidektClient
    API_HOST = "archidekt.com".freeze
    USER_AGENT = "PodTracker/0.1 (+https://pod-tracker.app; github.com/dunamismax/pod-tracker)".freeze
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

    def fetch_deck(deck_id)
      uri = URI("https://#{API_HOST}/api/decks/#{deck_id}/")
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
      raise TransportError, "Could not reach Archidekt: #{e.message}"
    end

    private

    def handle_response(response)
      case response.code.to_i
      when 200
        JSON.parse(response.body)
      when 404
        raise NotFoundError, "Archidekt deck not found"
      when 429
        raise RateLimitedError, "Archidekt rate-limited the request"
      else
        raise Error, "Archidekt request failed: HTTP #{response.code}"
      end
    rescue JSON::ParserError => e
      raise Error, "Archidekt returned malformed JSON: #{e.message}"
    end
  end
end
