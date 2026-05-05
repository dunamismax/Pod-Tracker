require "application_system_test_case"

class GameNightFlowTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @deck_a = @user.decks.create!(
      name: "Krenko Goblins",
      commander_names: [ "Krenko, Mob Boss" ]
    )
    @deck_b = @user.decks.create!(
      name: "Omnath Stompy",
      commander_names: [ "Omnath, Locus of Mana" ]
    )
  end

  test "user creates a session, seats a pod, records a result, and sees the summary" do
    sign_in_through_ui(@user)

    visit new_game_night_path
    fill_in "Session name", with: "Friday Commander"
    fill_in "Date", with: "2026-05-05"
    fill_in "game_night_form_check_ins_0_player_name", with: "Mara"
    select @deck_a.name, from: "game_night_form_check_ins_0_deck_id"
    fill_in "game_night_form_check_ins_1_player_name", with: "Stephen"
    select @deck_b.name, from: "game_night_form_check_ins_1_deck_id"
    click_button "Create session"

    assert_text "Session created."
    assert_text "Pod seating"
    click_button "Seat pods"

    assert_text "Pods seated."
    assert_text "Session summary"
    select "Mara", from: "results_rows_0_winner_player_id"
    fill_in "results_rows_0_turns", with: "8"
    fill_in "results_rows_0_win_condition", with: "Combat damage"
    fill_in "results_rows_0_notes", with: "Krenko went wide."
    click_button "Save results"

    assert_text "Results recorded."
    assert_text "Mara won"
    assert_text "Combat damage"
    assert_text "Krenko went wide."
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
