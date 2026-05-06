require "test_helper"

module Matchups
  class SessionContextTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @deck = @user.decks.create!(name: "Krenko Goblins", commander_names: [ "Krenko, Mob Boss" ])
      @commander = @deck.commanders.create!(name: "Krenko, Mob Boss", position: 1)
      @opponent = @user.players.create!(name: "Mara")
      @pilot = @user.players.create!(name: "Stephen")
      @game_night = @user.game_nights.create!(name: "Friday Commander", played_on: Date.new(2026, 5, 6))
      @night_deck = @game_night.game_night_decks.create!(player: @pilot, deck: @deck, position: 1)
    end

    test "returns prior notes for seated decks commanders and opponents" do
      deck_note = @user.matchup_notes.create!(
        deck: @deck,
        body: "Dies to one board wipe.",
        happened_at: 2.days.ago
      )
      commander_note = @user.matchup_notes.create!(
        deck: @deck,
        commander: @commander,
        body: "Krenko needs early removal.",
        happened_at: 1.day.ago
      )
      opponent_note = @user.matchup_notes.create!(
        deck: @deck,
        opponent: @opponent,
        body: "Mara keeps instant-speed answers.",
        happened_at: 3.days.ago
      )
      current_session_note = @user.matchup_notes.create!(
        deck: @deck,
        game_night: @game_night,
        body: "Do not show while seating this same session.",
        happened_at: Time.current
      )

      notes = Matchups::SessionContext.for_seating(
        user: @user,
        game_night: @game_night,
        seating_rows: [
          { "player_id" => @pilot.id.to_s, "pod_number" => "1", "seat_number" => "1" },
          { "player_id" => @opponent.id.to_s, "pod_number" => "1", "seat_number" => "2" }
        ],
        decks_by_player_id: { @pilot.id => @night_deck }
      )

      assert_equal [ commander_note, deck_note, opponent_note ], notes.fetch(1).to_a
      assert_not_includes notes.fetch(1), current_session_note
    end
  end
end
