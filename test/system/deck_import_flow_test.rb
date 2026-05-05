require "application_system_test_case"

class DeckImportFlowTest < ApplicationSystemTestCase
  test "user pastes a decklist and lands on the deck show page" do
    user = users(:one)
    sign_in_through_ui(user)

    visit new_deck_path
    fill_in "Deck name (optional)", with: "Atraxa Brew"
    fill_in "deck_import_form_decklist", with: <<~TXT
      Commander
      1 Atraxa, Praetors' Voice

      Mainboard
      1 Sol Ring
      1 Arcane Signet
      1 Command Tower
    TXT
    click_button "Import deck"

    assert_text "Deck imported."
    assert_text "Atraxa Brew"
    assert_text "Atraxa, Praetors' Voice"
    assert_text "Sol Ring"
    assert_text "Deterministic analysis"
    assert_text "Power"
    assert_text "Salt"
    assert_text "Social friction"
  end

  private
    def sign_in_through_ui(user, password: "password")
      visit new_session_path
      fill_in "email_address", with: user.email_address
      fill_in "password", with: password
      click_button "Sign in"
      assert_text "Ideal Magic"
    end
end
