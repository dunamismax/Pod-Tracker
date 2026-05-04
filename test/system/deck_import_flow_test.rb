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
  end

  test "blank decklist is rejected with an inline error" do
    user = users(:one)
    sign_in_through_ui(user)

    visit new_deck_path
    click_button "Import deck"

    assert_text(/required/i)
  end

  test "user uploads a text file decklist" do
    user = users(:one)
    sign_in_through_ui(user)

    decklist = <<~TXT
      Commander
      1 Atraxa, Praetors' Voice

      Mainboard
      1 Sol Ring
      1 Arcane Signet
      1 Command Tower
    TXT
    tempfile = Tempfile.new([ "uploaded-deck", ".txt" ])
    tempfile.binmode
    tempfile.write(decklist)
    tempfile.close

    visit new_deck_path
    fill_in "Deck name (optional)", with: "Uploaded Atraxa"
    attach_file "deck_import_form_decklist_file", tempfile.path

    click_button "Import deck"

    assert_text "Deck imported."
    assert_text "Uploaded Atraxa"
    assert_text "Atraxa, Praetors' Voice"
    assert_text "Sol Ring"
  ensure
    tempfile&.unlink
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
