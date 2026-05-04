require "json"

module Decks
  class FixtureLibrary
    DEFAULT_ROOT = Rails.root.join("db/seeds/commander/deck_fixtures")
    MANIFEST_FILENAME = "manifest.json"

    Entry = Struct.new(
      :slug, :name, :format, :color_identity, :expected_main_card_count,
      :intent, :power_band, :path, keyword_init: true
    ) do
      def text
        Pathname(path).read
      end

      def parse
        TextDecklistParser.new.parse(text)
      end
    end

    def initialize(root: DEFAULT_ROOT)
      @root = Pathname(root)
    end

    def entries
      @entries ||= load_entries
    end

    def find!(slug)
      entries.find { |entry| entry.slug == slug } ||
        raise(ArgumentError, "Unknown deck fixture: #{slug.inspect}")
    end

    def slugs
      entries.map(&:slug)
    end

    def manifest
      @manifest ||= JSON.parse(@root.join(MANIFEST_FILENAME).read)
    end

    def build_deck(slug, user: nil)
      entry = find!(slug)
      result = entry.parse
      deck = Deck.new(
        user: user,
        name: entry.name,
        format: entry.format,
        status: "imported",
        visibility: "private",
        source_type: "fixture",
        color_identity: entry.color_identity,
        commander_names: result.commanders.map { |c| c[:name] },
        last_imported_at: Time.current,
        import_metadata: {
          "fixture_slug" => entry.slug,
          "fixture_path" => entry.path.to_s,
          "intent" => entry.intent,
          "power_band" => entry.power_band
        }
      )

      result.commanders.each do |attrs|
        deck.commanders.build(
          name: attrs[:name],
          position: attrs[:position] || 1,
          raw_line: raw_line_for(attrs)
        )
      end

      result.boards.each do |board, entries|
        entries.each do |attrs|
          deck.deck_cards.build(
            name: attrs[:name],
            quantity: attrs[:quantity],
            board: board,
            position: attrs[:position],
            raw_line: raw_line_for(attrs),
            metadata: card_metadata(attrs)
          )
        end
      end

      deck
    end

    private

    def load_entries
      Array(manifest["decks"]).map do |attrs|
        Entry.new(
          slug: attrs.fetch("slug"),
          name: attrs.fetch("name"),
          format: attrs.fetch("format"),
          color_identity: Array(attrs["color_identity"]),
          expected_main_card_count: attrs["expected_main_card_count"],
          intent: attrs["intent"],
          power_band: attrs["power_band"],
          path: @root.join(attrs.fetch("file"))
        )
      end
    end

    def raw_line_for(attrs)
      base = "#{attrs[:quantity]} #{attrs[:name]}"
      base += " (#{attrs[:set]})" if attrs[:set].present?
      base += " #{attrs[:collector_number]}" if attrs[:collector_number].present?
      base
    end

    def card_metadata(attrs)
      metadata = {}
      metadata["set_code"] = attrs[:set] if attrs[:set].present?
      metadata["collector_number"] = attrs[:collector_number] if attrs[:collector_number].present?
      metadata
    end
  end
end
