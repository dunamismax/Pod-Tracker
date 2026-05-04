require "test_helper"

module Decks
  class FixtureLibraryTest < ActiveSupport::TestCase
    test "every manifest entry parses to the expected mainboard card count" do
      library = FixtureLibrary.new

      assert_not_empty(library.entries)

      library.entries.each do |entry|
        assert(entry.path.exist?, "Missing fixture file for #{entry.slug}: #{entry.path}")
        result = entry.parse
        assert_equal(
          entry.expected_main_card_count, result.main_card_count,
          "Mainboard card count mismatch for #{entry.slug}"
        )
        assert_equal(1, result.commanders.size, "#{entry.slug} should declare exactly one commander entry")
        assert_empty(result.unparsed_lines, "#{entry.slug} produced unparsed lines: #{result.unparsed_lines.inspect}")
      end
    end

    test "build_deck assembles persistable deck records with deck cards and a commander" do
      library = FixtureLibrary.new
      deck = library.build_deck("mono_green_omnath_stompy")

      assert_equal("Omnath Mono-Green Stompy", deck.name)
      assert_equal("commander", deck.format)
      assert_equal([ "G" ], deck.color_identity)
      assert_equal([ "Omnath, Locus of Mana" ], deck.commander_names)

      commander = deck.commanders.first
      assert_equal("Omnath, Locus of Mana", commander.name)
      assert_equal(1, commander.position)

      main_cards = deck.deck_cards.select { |dc| dc.board == "main" }
      assert_equal(99, main_cards.sum(&:quantity))
      assert(deck.save, "expected fixture deck to save: #{deck.errors.full_messages.inspect}")
    end

    test "find! raises for unknown slugs and returns the matching entry otherwise" do
      library = FixtureLibrary.new
      assert_raises(ArgumentError) { library.find!("does-not-exist") }
      assert_equal("krenko_goblin_tribal", library.find!("krenko_goblin_tribal").slug)
    end
  end
end
