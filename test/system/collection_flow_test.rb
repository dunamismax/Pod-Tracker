require "application_system_test_case"

class CollectionFlowTest < ApplicationSystemTestCase
  test "user imports collection cards and sees deck gaps" do
    user = users(:one)
    create_oracle_card("Atraxa, Praetors' Voice")
    create_oracle_card("Sol Ring")
    create_oracle_card("Command Tower")
    deck = create_deck_for(user)
    second_deck = create_deck_for(user, name: "Tower Backup")

    sign_in_through_ui(user)
    visit collection_path
    fill_in "collection_import_form_collection_list", with: "1 Sol Ring"
    click_button "Import collection"

    assert_text "Collection imported."
    assert_text "1 cards imported"

    visit collection_path
    assert_text "Demand pressure"
    assert_text "Command Tower"
    assert_text "across 2 decks"
    assert_text second_deck.name

    visit deck_path(deck)
    assert_text "Collection fit"
    assert_text "1/3 cards owned"
    assert_text "Command Tower"
    assert_text "Atraxa, Praetors' Voice"
  end

  private

    def sign_in_through_ui(user, password: "password")
      visit new_session_path
      fill_in "email_address", with: user.email_address
      fill_in "password", with: password
      click_button "Sign in"
      assert_text "Pod Tracker"
    end

    def create_oracle_card(name)
      OracleCard.create!(
        name: name,
        normalized_name: ApplicationRecord.normalize_card_name(name),
        scryfall_oracle_id: SecureRandom.uuid
      )
    end

    def create_deck_for(user, name: "Atraxa Brew")
      deck = user.decks.create!(
        name: name,
        format: "commander",
        status: "imported",
        visibility: "private",
        commander_names: [ "Atraxa, Praetors' Voice" ],
        source_type: "pasted_text"
      )
      deck.commanders.create!(name: "Atraxa, Praetors' Voice", position: 1)
      deck.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 1)
      deck.deck_cards.create!(name: "Command Tower", quantity: 1, board: "main", position: 2)
      deck
    end
end
