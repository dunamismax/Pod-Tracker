require "test_helper"

class GameNightsControllerTest < ActionDispatch::IntegrationTest
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

  test "requires authentication for sessions" do
    get game_nights_path
    assert_redirected_to new_session_path
  end

  test "renders the new session form" do
    sign_in_as(@user)

    get new_game_night_path

    assert_response :success
    assert_select "h1", "Start a session"
    assert_select "select[name='game_night_form[check_ins][0][deck_id]']"
  end

  test "creates a session and checks in players with their decks" do
    sign_in_as(@user)

    assert_difference -> { @user.game_nights.count } => 1,
                      -> { @user.players.count } => 2,
                      -> { GameNightPlayer.count } => 2,
                      -> { GameNightDeck.count } => 2,
                      -> { AuditEvent.where(event_name: "game_night.created").count } => 1 do
      post game_nights_path, params: {
        game_night_form: {
          name: "Friday Commander",
          played_on: "2026-05-05",
          location: "Kitchen table",
          check_ins: {
            "0" => { player_name: "Mara", deck_id: @deck_a.id },
            "1" => { player_name: "Stephen", deck_id: @deck_b.id }
          }
        }
      }
    end

    game_night = @user.game_nights.order(:id).last
    assert_redirected_to game_night_path(game_night)
    assert_equal "Kitchen table", game_night.location
    assert_equal [ "Mara", "Stephen" ], game_night.players.order(:name).pluck(:name)
    assert_equal [ "Krenko Goblins", "Omnath Stompy" ], game_night.game_night_decks.order(:position).pluck(:deck_name_snapshot)

    audit = AuditEvent.where(event_name: "game_night.created").last
    assert_equal 2, audit.metadata["checked_in_count"]
  end

  test "rejects sessions without a checked-in deck" do
    sign_in_as(@user)

    assert_no_difference -> { GameNight.count } do
      post game_nights_path, params: {
        game_night_form: {
          name: "Incomplete",
          played_on: "2026-05-05",
          check_ins: {
            "0" => { player_name: "Mara", deck_id: "" }
          }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "li", /needs a deck/
  end

  test "shows and removes a session" do
    sign_in_as(@user)
    game_night = @user.game_nights.create!(name: "Friday Commander", played_on: Date.new(2026, 5, 5))
    player = @user.players.create!(name: "Mara")
    game_night.game_night_players.create!(player: player, position: 1)
    game_night.game_night_decks.create!(player: player, deck: @deck_a, position: 1)

    get game_night_path(game_night)
    assert_response :success
    assert_select "h1", "Friday Commander"
    assert_select "p", /Krenko Goblins/

    assert_difference -> { GameNight.count } => -1 do
      delete game_night_path(game_night)
    end
    assert_redirected_to game_nights_path
  end
end
