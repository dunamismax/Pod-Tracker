require "test_helper"

module CommanderFormat
  class LegalitySnapshotImporterTest < ActiveSupport::TestCase
    test "imports the source-controlled commander rules and banlist snapshot" do
      snapshot = LegalitySnapshotImporter.new.import!

      assert_equal("mtgcommander", snapshot.source)
      assert_equal("commander", snapshot.format)
      assert_equal(Date.new(2024, 9, 23), snapshot.effective_on)
      assert_equal(Date.new(2026, 5, 4), snapshot.source_checked_on)
      assert(snapshot.banned_card?("Dockside Extortionist"))
      assert(snapshot.banned_card?("Mana Crypt"))
      assert(snapshot.banned_card?("Yawgmoth's Bargain"))
      assert_not snapshot.banned_card?("Sol Ring")
      assert_empty(snapshot.restricted_names)
      assert_equal(3, snapshot.category_bans.size)
      assert_equal(100, snapshot.rules_snapshot.dig("deck_construction", "deck_size_including_commander"))
      assert_equal(40, snapshot.rules_snapshot.dig("play", "starting_life_total"))
      assert_equal(21, snapshot.rules_snapshot.dig("play", "commander_damage_loss_threshold"))
    end

    test "updates the same effective snapshot idempotently" do
      importer = LegalitySnapshotImporter.new
      first = importer.import!
      second = importer.import!

      assert_equal(first.id, second.id)
      assert_equal(1, LegalitySnapshot.where(source: "mtgcommander", format: "commander").count)
    end
  end
end
