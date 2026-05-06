module Collections
  class Ownership
    Entry = Struct.new(:name, :normalized_name, :board, :required_quantity, :owned_quantity, keyword_init: true) do
      def missing_quantity
        [ required_quantity - owned_quantity, 0 ].max
      end

      def owned?
        missing_quantity.zero?
      end
    end

    Result = Struct.new(:entries, keyword_init: true) do
      def owned_count
        entries.sum { |entry| [ entry.required_quantity, entry.owned_quantity ].min }
      end

      def required_count
        entries.sum(&:required_quantity)
      end

      def missing_count
        entries.sum(&:missing_quantity)
      end

      def complete?
        missing_count.zero?
      end

      def missing_entries
        entries.reject(&:owned?)
      end
    end

    def self.for_deck(user:, deck:, collection_quantities: nil)
      new(user:, deck:, collection_quantities:).call
    end

    def initialize(user:, deck:, collection_quantities: nil)
      @user = user
      @deck = deck
      @collection_quantities = collection_quantities
    end

    def call
      collection_quantities = @collection_quantities || @user.collection_cards.pluck(:normalized_name, :quantity).to_h
      required_entries = grouped_deck_entries

      entries = required_entries.map do |key, attrs|
        Entry.new(
          name: attrs[:name],
          normalized_name: key,
          board: attrs[:board],
          required_quantity: attrs[:quantity],
          owned_quantity: collection_quantities.fetch(key, 0)
        )
      end

      Result.new(entries: entries.sort_by { |entry| [ entry.owned? ? 1 : 0, entry.board, entry.name ] })
    end

    private

      def grouped_deck_entries
        grouped = {}

        @deck.commanders.each do |commander|
          add_entry(grouped, commander.normalized_name, commander.name, "commander", 1)
        end

        @deck.deck_cards.where(board: %w[main commander]).each do |card|
          add_entry(grouped, card.normalized_name, card.name, card.board, card.quantity)
        end

        grouped
      end

      def add_entry(grouped, normalized_name, name, board, quantity)
        key = normalized_name.presence || ApplicationRecord.normalize_card_name(name)
        grouped[key] ||= { name:, board:, quantity: 0 }
        grouped[key][:quantity] += quantity.to_i
      end
  end
end
