require "test_helper"

module Decks
  class TextDecklistParserTest < ActiveSupport::TestCase
    test "parses pasted decklist with explicit commander and mainboard sections" do
      text = <<~TXT
        # Commander
        1 Atraxa, Praetors' Voice

        # Mainboard
        1 Sol Ring
        1 Arcane Signet
        2 Plains
        // commentary line is ignored
        1 Counterspell
      TXT

      result = TextDecklistParser.new.parse(text)

      assert_equal([ "Atraxa, Praetors' Voice" ], result.commanders.map { |c| c[:name] })
      assert_equal(1, result.commander_count)
      assert_equal(5, result.main_card_count)
      assert_equal(6, result.total_card_count)
      assert_equal([ "Sol Ring", "Arcane Signet", "Plains", "Counterspell" ], result.card_entries("main").map { |c| c[:name] })
      assert_equal([ 1, 2, 3, 4 ], result.card_entries("main").map { |c| c[:position] })
      assert_equal(2, result.card_entries("main")[2][:quantity])
      assert_equal([], result.unparsed_lines)
    end

    test "defaults to mainboard when no headers are present and supports x quantity prefixes" do
      text = <<~TXT
        4x Lightning Bolt
        1 Sol Ring
        29 Mountain
      TXT

      result = TextDecklistParser.new.parse(text)

      assert_equal([], result.commanders)
      assert_equal(34, result.main_card_count)
      assert_equal(4, result.card_entries("main").first[:quantity])
    end

    test "captures unparsed lines instead of dropping them silently" do
      text = <<~TXT
        not a card line
        1 Sol Ring
      TXT

      result = TextDecklistParser.new.parse(text)

      assert_equal([ "not a card line" ], result.unparsed_lines)
      assert_equal(1, result.main_card_count)
    end

    test "supports sideboard and maybeboard headers" do
      text = <<~TXT
        # Mainboard
        1 Sol Ring

        # Sideboard
        1 Pithing Needle

        # Maybeboard
        1 Reliquary Tower
      TXT

      result = TextDecklistParser.new.parse(text)

      assert_equal(1, result.card_entries("main").size)
      assert_equal("Pithing Needle", result.card_entries("sideboard").first[:name])
      assert_equal("Reliquary Tower", result.card_entries("maybeboard").first[:name])
    end

    test "extracts set code and collector number when present" do
      text = "1 Sol Ring (cmm) 410\n"
      result = TextDecklistParser.new.parse(text)

      entry = result.card_entries("main").first
      assert_equal("Sol Ring", entry[:name])
      assert_equal("cmm", entry[:set])
      assert_equal("410", entry[:collector_number])
    end
  end
end
