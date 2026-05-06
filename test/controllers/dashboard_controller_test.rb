require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "renders commander meta from completed session results" do
    user = users(:one)
    sign_in_as(user)
    deck = user.decks.create!(name: "Krenko Goblins", commander_names: [ "Krenko, Mob Boss" ])
    other_deck = user.decks.create!(name: "Omnath Stompy", commander_names: [ "Omnath, Locus of Mana" ])
    pilot = user.players.create!(name: "Mara")
    opponent = user.players.create!(name: "Stephen")
    game_night = user.game_nights.create!(
      name: "Friday Commander",
      played_on: Date.new(2026, 5, 6),
      status: "completed"
    )
    game_night.game_night_pod_seats.create!(player: pilot, deck: deck, pod_number: 1, seat_number: 1)
    game_night.game_night_pod_seats.create!(player: opponent, deck: other_deck, pod_number: 1, seat_number: 2)
    game_night.game_night_pod_results.create!(pod_number: 1, winner_player: pilot, turns: 7)

    get app_dashboard_path

    assert_response :success
    assert_select "h2", "Commander meta"
    assert_select "td", "Krenko, Mob Boss"
    assert_select "td", /thin sample/
  end
end
