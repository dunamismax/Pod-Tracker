require "set"

module Collections
  class DemandPressure
    Entry = Struct.new(
      :name, :normalized_name, :total_missing_quantity, :deck_count, :deck_names,
      keyword_init: true
    )

    Result = Struct.new(:entries, keyword_init: true) do
      def shared_entries
        entries.select { |entry| entry.deck_count > 1 }
      end

      def any?
        entries.any?
      end
    end

    def self.for_user(user:, limit: 12)
      new(user:, limit:).call
    end

    def initialize(user:, limit: 12)
      @user = user
      @limit = limit
    end

    def call
      collection_quantities = @user.collection_cards.pluck(:normalized_name, :quantity).to_h
      pressure = Hash.new { |hash, key| hash[key] = { name: nil, missing: 0, deck_names: Set.new } }

      @user.decks.includes(:commanders, :deck_cards).find_each do |deck|
        missing_for_deck(deck, collection_quantities).each do |entry|
          bucket = pressure[entry.normalized_name]
          bucket[:name] ||= entry.name
          bucket[:missing] += entry.missing_quantity
          bucket[:deck_names] << deck.name
        end
      end

      entries = pressure.map do |normalized_name, attrs|
        Entry.new(
          name: attrs[:name],
          normalized_name: normalized_name,
          total_missing_quantity: attrs[:missing],
          deck_count: attrs[:deck_names].size,
          deck_names: attrs[:deck_names].to_a.sort
        )
      end

      Result.new(entries: entries.sort_by { |entry| [ -entry.deck_count, -entry.total_missing_quantity, entry.name ] }.first(@limit))
    end

    private

      def missing_for_deck(deck, collection_quantities)
        Collections::Ownership
          .for_deck(user: @user, deck:, collection_quantities:)
          .missing_entries
      end
  end
end
