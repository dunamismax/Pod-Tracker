require "test_helper"

class MatchupNoteTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = @user.decks.create!(name: "Krenko Goblins", commander_names: [ "Krenko, Mob Boss" ])
    @commander = @deck.commanders.create!(name: "Krenko, Mob Boss", position: 1)
  end

  test "normalizes tags" do
    note = @user.matchup_notes.create!(
      deck: @deck,
      commander: @commander,
      body: "Krenko rebuilt after two wipes.",
      tag_list: "Go Wide, #Resilience, go wide",
      happened_at: Time.current
    )

    assert_equal [ "go wide", "resilience" ], note.tags
  end

  test "requires commander to belong to selected deck" do
    other_deck = @user.decks.create!(name: "Omnath Stompy", commander_names: [ "Omnath, Locus of Mana" ])
    other_commander = other_deck.commanders.create!(name: "Omnath, Locus of Mana", position: 1)

    note = @user.matchup_notes.new(
      deck: @deck,
      commander: other_commander,
      body: "Wrong commander link.",
      happened_at: Time.current
    )

    assert_not note.valid?
    assert_includes note.errors[:commander], "must belong to the selected deck"
  end

  test "rejects records linked to another user's player" do
    other_user = users(:two)
    opponent = other_user.players.create!(name: "Mara")

    note = @user.matchup_notes.new(
      deck: @deck,
      opponent: opponent,
      body: "Cross-account note.",
      happened_at: Time.current
    )

    assert_not note.valid?
    assert_includes note.errors[:opponent], "does not belong to this account"
  end
end
