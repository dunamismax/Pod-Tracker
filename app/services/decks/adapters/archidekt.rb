require "uri"

module Decks
  module Adapters
    class Archidekt < Base
      SOURCE_TYPE = "archidekt_url".freeze
      ALLOWED_HOSTS = %w[archidekt.com www.archidekt.com].freeze
      DECK_ID_PATTERN = %r{/decks/(\d+)\b}.freeze

      class InvalidUrl < StandardError; end
      class FetchFailed < StandardError; end

      class << self
        attr_accessor :client_factory
      end
      self.client_factory = -> { ArchidektClient.new }

      def initialize(client: nil)
        @client = client || self.class.client_factory.call
      end

      def source_type
        SOURCE_TYPE
      end

      def parse(payload)
        url = payload.to_s.strip
        deck_id = extract_deck_id(url)
        normalized_url = "https://archidekt.com/decks/#{deck_id}"
        json = fetch_with_translation(deck_id)
        translate(json, source_url: normalized_url, deck_id: deck_id)
      end

      def fetch(payload)
        parse(payload)
      end

      private

      def extract_deck_id(url)
        raise InvalidUrl, "Archidekt deck URL is required." if url.empty?

        uri = URI.parse(url)
        unless %w[http https].include?(uri.scheme)
          raise InvalidUrl, "Archidekt deck URL must use http or https."
        end
        unless ALLOWED_HOSTS.include?(uri.host&.downcase)
          raise InvalidUrl, "URL is not an Archidekt deck URL."
        end

        match = uri.path.to_s.match(DECK_ID_PATTERN)
        raise InvalidUrl, "Could not find an Archidekt deck ID in the URL." unless match

        match[1]
      rescue URI::InvalidURIError
        raise InvalidUrl, "That doesn't look like a valid URL."
      end

      def fetch_with_translation(deck_id)
        @client.fetch_deck(deck_id)
      rescue ArchidektClient::NotFoundError
        raise FetchFailed, "Archidekt deck not found. Make sure the deck is public."
      rescue ArchidektClient::RateLimitedError
        raise FetchFailed, "Archidekt is rate-limiting requests. Try again in a moment."
      rescue ArchidektClient::TransportError => e
        raise FetchFailed, e.message
      rescue ArchidektClient::Error => e
        raise FetchFailed, "Archidekt request failed: #{e.message}"
      end

      def translate(json, source_url:, deck_id:)
        cards = Array(json["cards"])
        category_map = build_category_map(json["categories"])

        commanders = []
        boards = Hash.new { |h, k| h[k] = [] }
        unparsed = []
        position = Hash.new(0)
        commander_position = 0

        cards.each do |entry|
          card_data = entry["card"] || {}
          oracle = card_data["oracleCard"] || {}
          edition = card_data["edition"] || {}
          name = (oracle["name"] || card_data["name"]).to_s.strip
          if name.empty?
            unparsed << "Archidekt card with missing name"
            next
          end

          quantity = entry["quantity"].to_i
          next if quantity <= 0

          set_code = (edition["editioncode"] || edition["editionCode"]).to_s.downcase
          set_code = nil if set_code.empty?
          collector_number = (card_data["collectorNumber"] || card_data["collector_number"]).to_s
          collector_number = nil if collector_number.empty?

          card_categories = Array(entry["categories"]).map(&:to_s)
          routing = route_card(card_categories, category_map)
          next if routing.nil?

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
            boards[routing] << attrs.merge(board: routing, position: position[routing])
          end
        end

        ParsedDeck.new(
          name: json["name"].to_s.strip.presence,
          commanders: commanders,
          boards: boards.transform_values(&:itself),
          unparsed_lines: unparsed,
          source_type: SOURCE_TYPE,
          source_url: source_url,
          source_metadata: {
            "archidekt_deck_id" => deck_id.to_s,
            "card_count" => cards.size,
            "commander_count" => commanders.size
          }
        )
      end

      def build_category_map(raw_categories)
        map = {}
        Array(raw_categories).each do |cat|
          name = cat.is_a?(Hash) ? cat["name"].to_s : cat.to_s
          next if name.empty?
          map[name.downcase] = cat.is_a?(Hash) ? cat : { "name" => name }
        end
        map
      end

      def route_card(card_categories, category_map)
        matched = card_categories.map { |c| category_map[c.downcase] }.compact
        return "commander" if matched.any? { |c| c["isPremier"] == true }

        card_categories.each do |c|
          case c.downcase
          when "sideboard" then return "sideboard"
          when "maybeboard" then return "maybeboard"
          end
        end

        if matched.any? && matched.all? { |c| c["includedInDeck"] == false }
          return nil
        end

        "main"
      end
    end
  end
end
