require "test_helper"

class GameNightFormTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = @user.decks.create!(name: "Krenko", commander_names: [ "Krenko, Mob Boss" ])
  end

  test "accepts populated player and deck check-ins" do
    form = GameNightForm.new(
      name: "Friday Commander",
      played_on: Date.current,
      check_ins: {
        "0" => { "player_name" => "Mara", "deck_id" => @deck.id.to_s },
        "1" => { "player_name" => "", "deck_id" => "" }
      }
    )
    form.user = @user

    assert_predicate form, :valid?
    assert_equal 1, form.populated_check_ins.size
  end

  test "rejects incomplete or unowned check-ins" do
    other_deck = users(:two).decks.create!(name: "Other Deck")
    form = GameNightForm.new(
      name: "Friday Commander",
      played_on: Date.current,
      check_ins: {
        "0" => { "player_name" => "Mara", "deck_id" => other_deck.id.to_s },
        "1" => { "player_name" => "Mara", "deck_id" => @deck.id.to_s },
        "2" => { "player_name" => "No Deck", "deck_id" => "" }
      }
    )
    form.user = @user

    assert_not form.valid?
    assert_includes form.errors[:check_ins], "include decks not owned by you"
    assert_includes form.errors[:check_ins], "must use each player only once"
    assert_includes form.errors[:check_ins], "row 3 needs a deck"
  end
end
