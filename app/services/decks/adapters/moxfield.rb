require "uri"

module Decks
  module Adapters
    class Moxfield < Base
      SOURCE_TYPE = "moxfield_url".freeze
      ALLOWED_HOSTS = %w[moxfield.com www.moxfield.com].freeze
      DECK_SLUG_PATTERN = %r{/decks/([A-Za-z0-9_\-]+)\b}.freeze

      BOARD_ROUTING = {
        "commanders" => "commander",
        "mainboard" => "main",
        "main" => "main",
        "sideboard" => "sideboard",
        "maybeboard" => "maybeboard",
        "companions" => "sideboard"
      }.freeze

      class InvalidUrl < StandardError; end
      class FetchFailed < StandardError; end

      class << self
        attr_accessor :client_factory
      end
      self.client_factory = -> { MoxfieldClient.new }

      def initialize(client: nil)
        @client = client || self.class.client_factory.call
      end

      def source_type
        SOURCE_TYPE
      end

      def parse(payload)
        url = payload.to_s.strip
        slug = extract_slug(url)
        normalized_url = "https://www.moxfield.com/decks/#{slug}"
        json = fetch_with_translation(slug)
        translate(json, source_url: normalized_url, slug: slug)
      end

      def fetch(payload)
        parse(payload)
      end

      private

      def extract_slug(url)
        raise InvalidUrl, "Moxfield deck URL is required." if url.empty?

        uri = URI.parse(url)
        unless %w[http https].include?(uri.scheme)
          raise InvalidUrl, "Moxfield deck URL must use http or https."
        end
        unless ALLOWED_HOSTS.include?(uri.host&.downcase)
          raise InvalidUrl, "URL is not a Moxfield deck URL."
        end

        match = uri.path.to_s.match(DECK_SLUG_PATTERN)
        raise InvalidUrl, "Could not find a Moxfield deck ID in the URL." unless match

        match[1]
      rescue URI::InvalidURIError
        raise InvalidUrl, "That doesn't look like a valid URL."
      end

      def fetch_with_translation(slug)
        @client.fetch_deck(slug)
      rescue MoxfieldClient::NotFoundError
        raise FetchFailed, "Moxfield deck not found. Make sure the deck is public."
      rescue MoxfieldClient::RateLimitedError
        raise FetchFailed, "Moxfield is rate-limiting requests. Try again in a moment."
      rescue MoxfieldClient::TransportError => e
        raise FetchFailed, e.message
      rescue MoxfieldClient::Error => e
        raise FetchFailed, "Moxfield request failed: #{e.message}"
      end

      def translate(json, source_url:, slug:)
        boards = extract_boards(json)

        commanders = []
        result_boards = Hash.new { |h, k| h[k] = [] }
        unparsed = []
        position = Hash.new(0)
        commander_position = 0
        total_card_entries = 0

        boards.each do |raw_name, board_payload|
          routing = BOARD_ROUTING[raw_name.to_s.downcase]
          next if routing.nil?

          card_entries(board_payload).each do |entry|
            total_card_entries += 1
            card_data = entry["card"] || {}
            name = (card_data["name"] || entry["name"]).to_s.strip
            if name.empty?
              unparsed << "Moxfield card with missing name in #{raw_name}"
              next
            end

            quantity = entry["quantity"].to_i
            next if quantity <= 0

            set_code = card_data["set"].to_s.downcase
            set_code = nil if set_code.empty?
            collector_number = (card_data["cn"] || card_data["collector_number"]).to_s
            collector_number = nil if collector_number.empty?

            attrs = {
              quantity: quantity,
              name: name,
              set: set_code,
              collector_number: collector_number
            }

            if routing == "commander"
              commander_position += 1
              commanders << attrs.merge(board: "commander", position: commander_position)
            else
              position[routing] += 1
              result_boards[routing] << attrs.merge(board: routing, position: position[routing])
            end
          end
        end

        ParsedDeck.new(
          name: (json["name"] || json["deckName"]).to_s.strip.presence,
          commanders: commanders,
          boards: result_boards.transform_values(&:itself),
          unparsed_lines: unparsed,
          source_type: SOURCE_TYPE,
          source_url: source_url,
          source_metadata: {
            "moxfield_deck_id" => slug.to_s,
            "card_count" => total_card_entries,
            "commander_count" => commanders.size
          }
        )
      end

      def extract_boards(json)
        nested = json["boards"]
        return nested if nested.is_a?(Hash)

        flat = {}
        BOARD_ROUTING.each_key do |key|
          value = json[key]
          flat[key] = value if value.is_a?(Hash)
        end
        flat
      end

      def card_entries(board_payload)
        return [] unless board_payload.is_a?(Hash)

        cards = board_payload["cards"]
        cards = board_payload if cards.nil?
        return [] unless cards.is_a?(Hash)

        cards.values.select { |entry| entry.is_a?(Hash) }
      end
    end
  end
end
