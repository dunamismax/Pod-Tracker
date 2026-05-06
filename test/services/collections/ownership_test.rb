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

    test "demand pressure ranks missing cards shared by multiple decks" do
      second_deck = @user.decks.create!(
        name: "Tower Matters",
        format: "commander",
        status: "imported",
        visibility: "private",
        commander_names: [ "Atraxa, Praetors' Voice" ]
      )
      second_deck.deck_cards.create!(name: "Command Tower", oracle_card: @command_tower, quantity: 1, board: "main", position: 1)
      second_deck.deck_cards.create!(name: "Atraxa, Praetors' Voice", oracle_card: @atraxa, quantity: 1, board: "main", position: 2)

      result = DemandPressure.for_user(user: @user)

      assert_equal "Atraxa, Praetors' Voice", result.entries.first.name
      assert_equal 2, result.entries.first.deck_count
      assert_equal 2, result.entries.first.total_missing_quantity
      assert_includes result.entries.first.deck_names, "Atraxa Brew"
      assert_includes result.entries.first.deck_names, "Tower Matters"
    end

    test "recommendation ownership annotates owned options and acquisition gaps" do
      ramp_tag = CardTag.find_or_create_by!(slug: "ramp") do |tag|
        tag.category = "role"
        tag.label = "Ramp"
      end
      draw_tag = CardTag.find_or_create_by!(slug: "card_draw") do |tag|
        tag.category = "role"
        tag.label = "Card draw"
      end
      arcane_signet = create_oracle_card("Arcane Signet")
      rhystic_study = create_oracle_card("Rhystic Study")
      CardTagAssignment.find_or_create_by!(card_tag: ramp_tag, card_name: "Arcane Signet") do |assignment|
        assignment.oracle_card = arcane_signet
      end
      CardTagAssignment.find_or_create_by!(card_tag: draw_tag, card_name: "Rhystic Study") do |assignment|
        assignment.oracle_card = rhystic_study
      end
      @user.collection_cards.create!(name: "Arcane Signet", oracle_card: arcane_signet, quantity: 1)

      recommendations = [
        { "category" => "ramp", "title" => "Add ramp" },
        { "category" => "draw", "title" => "Add draw" }
      ]

      annotated = RecommendationOwnership.annotate(user: @user, deck: @deck, recommendations:)

      assert_equal "owned_options", annotated.first.dig("ownership", "status")
      assert_includes annotated.first.dig("ownership", "detail"), "Arcane Signet"
      assert_equal "needs_acquisition", annotated.second.dig("ownership", "status")
    end

    private

      def create_oracle_card(name, type_line: nil)
        OracleCard.create!(
          name: name,
          normalized_name: ApplicationRecord.normalize_card_name(name),
          scryfall_oracle_id: SecureRandom.uuid,
          type_line: type_line
        )
      end
  end
end
