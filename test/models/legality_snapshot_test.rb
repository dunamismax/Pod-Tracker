require "test_helper"

class LegalitySnapshotTest < ActiveSupport::TestCase
  test "normalizes ban lookups from stored card names" do
    snapshot = LegalitySnapshot.create!(
      source: "mtgcommander",
      effective_on: Date.new(2024, 9, 24),
      banned_names: [ " Mana Crypt ", "Nadu, Winged Wisdom", "Nadu, Winged Wisdom" ],
      category_bans: [ { "label" => "Cards that refer to ante" } ],
      rules_snapshot: { "play" => { "starting_life_total" => 40 } }
    )

    assert_equal([ "Mana Crypt", "Nadu, Winged Wisdom" ], snapshot.banned_names)
    assert_equal([ "mana crypt", "nadu winged wisdom" ], snapshot.banned_normalized_names)
    assert(snapshot.banned_card?("Nadu, Winged Wisdom"))
    assert(snapshot.banned_card?("nadu winged wisdom"))
    assert_not snapshot.banned_card?("Sol Ring")
    assert_equal([ "Cards that refer to ante" ], snapshot.category_ban_labels)
    assert_equal(40, snapshot.rules_snapshot.dig("play", "starting_life_total"))
  end

  test "current commander snapshot returns the newest effective source" do
    older = LegalitySnapshot.create!(
      source: "mtgcommander",
      effective_on: Date.new(2023, 1, 1),
      banned_names: [ "Biorhythm" ]
    )
    newer = LegalitySnapshot.create!(
      source: "mtgcommander",
      effective_on: Date.new(2025, 1, 1),
      banned_names: [ "Dockside Extortionist" ]
    )

    assert_equal(newer, LegalitySnapshot.current_commander)
    assert_not_equal(older, LegalitySnapshot.current_commander)
  end
end
