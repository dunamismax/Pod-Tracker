require "test_helper"

module Collections
  class OwnershipTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @atraxa = create_oracle_card("Atraxa, Praetors' Voice")
      @sol_ring = create_oracle_card("Sol Ring")
      @command_tower = create_oracle_card("Command Tower")

      @deck = @user.decks.create!(
        name: "Atraxa Brew",
        format: "commander",
        status: "imported",
        visibility: "private",
        commander_names: [ "Atraxa, Praetors' Voice" ]
      )
      @deck.commanders.create!(name: "Atraxa, Praetors' Voice", oracle_card: @atraxa, position: 1)
      @deck.deck_cards.create!(name: "Sol Ring", oracle_card: @sol_ring, quantity: 1, board: "main", position: 1)
      @deck.deck_cards.create!(name: "Command Tower", oracle_card: @command_tower, quantity: 1, board: "main", position: 2)

      @user.collection_cards.create!(name: "Sol Ring", oracle_card: @sol_ring, quantity: 1)
    end

    test "reports owned and missing quantities for a deck" do
      result = Ownership.for_deck(user: @user, deck: @deck)

      assert_equal 3, result.required_count
      assert_equal 1, result.owned_count
      assert_equal 2, result.missing_count

      missing_names = result.missing_entries.map(&:name)
      assert_includes missing_names, "Atraxa, Praetors' Voice"
      assert_includes missing_names, "Command Tower"
      assert_not_includes missing_names, "Sol Ring"
    end

    private

      def create_oracle_card(name)
        OracleCard.create!(
          name: name,
          normalized_name: ApplicationRecord.normalize_card_name(name),
          scryfall_oracle_id: SecureRandom.uuid
        )
      end
  end
end
