require "test_helper"

class MatchupNotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @deck = @user.decks.create!(name: "Krenko Goblins", commander_names: [ "Krenko, Mob Boss" ])
    @commander = @deck.commanders.create!(name: "Krenko, Mob Boss", position: 1)
    @opponent = @user.players.create!(name: "Mara")
    @game_night = @user.game_nights.create!(name: "Friday Commander", played_on: Date.new(2026, 5, 6))
    sign_in_as(@user)
  end

  test "creates, updates, searches, and removes a matchup note" do
    assert_difference -> { MatchupNote.count } => 1,
                      -> { AuditEvent.where(event_name: "matchup_note.created").count } => 1 do
      post matchup_notes_path, params: {
        matchup_note: {
          deck_id: @deck.id,
          commander_id: @commander.id,
          opponent_id: @opponent.id,
          game_night_id: @game_night.id,
          game_night_pod_number: 1,
          tag_list: "go wide, removal check",
          body: "Mara held removal until Krenko committed.",
          happened_at: Time.current
        }
      }
    end

    note = MatchupNote.last
    assert_redirected_to matchup_note_path(note)
    assert_equal [ "go wide", "removal check" ], note.tags

    get matchup_notes_path(tag: "removal check")
    assert_response :success
    assert_select "a", text: "Krenko Goblins"

    get matchup_notes_path(q: "held removal")
    assert_response :success
    assert_select "p", /Mara held removal/

    patch matchup_note_path(note), params: {
      matchup_note: {
        deck_id: @deck.id,
        body: "Updated note.",
        tag_list: "updated",
        happened_at: Time.current
      }
    }

    assert_redirected_to matchup_note_path(note)
    assert_equal "Updated note.", note.reload.body
    assert_equal [ "updated" ], note.tags

    pod = @user.pods.create!(name: "Friday pod")
    pod_note = @user.matchup_notes.create!(
      deck: @deck,
      pod: pod,
      body: "Saved pod matchup.",
      happened_at: Time.current
    )

    get matchup_notes_path(pod_id: pod.id)
    assert_response :success
    assert_select "p", /Saved pod matchup/
    assert_select "p", text: /Updated note\./, count: 0

    assert_difference -> { MatchupNote.count } => -1,
                      -> { AuditEvent.where(event_name: "matchup_note.removed").count } => 1 do
      delete matchup_note_path(note)
    end
    assert_redirected_to matchup_notes_path
    pod_note.destroy!
  end

  test "renders new and edit forms" do
    get new_matchup_note_path(deck_id: @deck.id, commander_id: @commander.id, opponent_id: @opponent.id, game_night_id: @game_night.id, game_night_pod_number: 1)

    assert_response :success
    assert_select "h1", "New matchup note"
    assert_select "textarea[name='matchup_note[body]']"

    note = @user.matchup_notes.create!(
      deck: @deck,
      commander: @commander,
      opponent: @opponent,
      body: "Mara kept removal open.",
      happened_at: Time.current
    )

    get edit_matchup_note_path(note)

    assert_response :success
    assert_select "h1", "Edit matchup note"
    assert_select "textarea", /Mara kept removal open/
  end

  test "does not expose another user's matchup note" do
    other_user = users(:two)
    other_deck = other_user.decks.create!(name: "Other Deck")
    note = other_user.matchup_notes.create!(
      deck: other_deck,
      body: "Private note.",
      happened_at: Time.current
    )

    get matchup_note_path(note)

    assert_response :not_found
  end
end
