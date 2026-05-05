require "test_helper"

class GameNightTest < ActiveSupport::TestCase
  test "players are user owned and normalized" do
    user = users(:one)
    player = user.players.create!(name: "  Mara   Quinn  ")

    assert_equal "Mara Quinn", player.name
    assert_equal "mara quinn", player.normalized_name
    assert_not user.players.build(name: "mara quinn").valid?
  end

  test "game night check-ins snapshot deck names and commanders" do
    user = users(:one)
    deck = user.decks.create!(
      name: "Voja Wolves",
      commander_names: [ "Voja, Jaws of the Conclave" ]
    )
    player = user.players.create!(name: "Mara")
    game_night = user.game_nights.create!(
      name: "Friday Commander",
      played_on: Date.new(2026, 5, 5)
    )

    game_night.game_night_players.create!(player: player, position: 1)
    night_deck = game_night.game_night_decks.create!(player: player, deck: deck, position: 1)
    deck.update!(name: "Voja Updated", commander_names: [ "Voja" ])

    assert_equal 1, game_night.checked_in_count
    assert_equal "Voja Wolves", night_deck.deck_name_snapshot
    assert_equal [ "Voja, Jaws of the Conclave" ], night_deck.commander_names_snapshot
  end

  test "pod seats snapshot decks and pod results require an outcome" do
    user = users(:one)
    deck = user.decks.create!(
      name: "Pantlaza Dinosaurs",
      commander_names: [ "Pantlaza, Sun-Favored" ]
    )
    player = user.players.create!(name: "Stephen")
    game_night = user.game_nights.create!(
      name: "Friday Commander",
      played_on: Date.new(2026, 5, 5)
    )

    seat = game_night.game_night_pod_seats.create!(
      player: player,
      deck: deck,
      pod_number: 1,
      seat_number: 1
    )
    result = game_night.game_night_pod_results.create!(
      pod_number: 1,
      winner_player: player,
      turns: 8,
      win_condition: "Combat damage"
    )

    assert_equal "Pantlaza Dinosaurs", seat.deck_name_snapshot
    assert_equal [ "Pantlaza, Sun-Favored" ], seat.commander_names_snapshot
    assert_predicate result, :valid?
    assert_not game_night.game_night_pod_results.build(pod_number: 2).valid?
  end
end
