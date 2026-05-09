require "csv"

module Decks
  class Exporter
    SCHEMA_VERSION = 1
    BOARD_LABELS = {
      "commander" => "Commander",
      "main" => "Mainboard",
      "sideboard" => "Sideboard",
      "maybeboard" => "Maybeboard",
      "companion" => "Companion"
    }.freeze
    BOARD_ORDER = %w[commander main sideboard maybeboard companion].freeze

    def initialize(deck, generated_at: Time.current)
      @deck = deck
      @generated_at = generated_at
    end

    def to_text
      sections = []
      sections << header_text
      BOARD_ORDER.each do |board|
        cards = cards_for(board)
        next if cards.empty?
        sections << "#{BOARD_LABELS[board]}\n" + cards.map { |c| "#{c.quantity} #{c.name}" }.join("\n")
      end
      sections.compact.join("\n\n") + "\n"
    end

    def to_csv
      CSV.generate do |csv|
        csv << %w[board quantity name]
        BOARD_ORDER.each do |board|
          cards_for(board).each do |card|
            csv << [ board, card.quantity, card.name ]
          end
        end
      end
    end

    def to_h
      {
        schema_version: SCHEMA_VERSION,
        generated_at: iso(@generated_at),
        deck: {
          id: @deck.id,
          name: @deck.name,
          format: @deck.format,
          status: @deck.status,
          source_type: @deck.source_type,
          commander_names: @deck.commander_names,
          last_imported_at: iso(@deck.last_imported_at),
          created_at: iso(@deck.created_at),
          updated_at: iso(@deck.updated_at),
          card_count: total_card_count,
          boards: BOARD_ORDER.each_with_object({}) do |board, memo|
            cards = cards_for(board)
            next if cards.empty?
            memo[board] = cards.map do |card|
              { name: card.name, quantity: card.quantity }
            end
          end
        }
      }
    end

    def to_json(*)
      JSON.pretty_generate(to_h)
    end

    def filename(extension)
      slug = @deck.name.to_s.gsub(/[^a-z0-9]+/i, "-").downcase.gsub(/^-+|-+$/, "").presence || "deck"
      stamp = @generated_at.utc.strftime("%Y%m%dT%H%M%SZ")
      "pod-tracker-deck-#{slug}-#{stamp}.#{extension}"
    end

    private
      def cards_for(board)
        @deck.deck_cards.where(board: board).order(:position, :name)
      end

      def total_card_count
        @deck.deck_cards.sum(:quantity)
      end

      def header_text
        lines = [ "# #{@deck.name}" ]
        if @deck.commander_names.present?
          lines << "# Commander: #{@deck.commander_names.join(', ')}"
        end
        lines << "# Exported #{@generated_at.utc.iso8601}"
        lines.join("\n")
      end

      def iso(value)
        value&.utc&.iso8601
      end
  end
end
