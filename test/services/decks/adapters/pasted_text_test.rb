require "test_helper"

module Decks
  module Adapters
    class PastedTextTest < ActiveSupport::TestCase
      DECKLIST = <<~TXT.freeze
        Commander
        1 Atraxa, Praetors' Voice

        Mainboard
        1 Sol Ring
        1 Arcane Signet
        1 Command Tower

        // a comment line
        // gibberish-without-a-quantity
      TXT

      test "source_type is pasted_text" do
        assert_equal "pasted_text", Adapters::PastedText.new.source_type
      end

      test "parse returns a structured ParsedDeck with commander and mainboard" do
        parsed = Adapters::PastedText.new.parse(DECKLIST)

        assert_equal "pasted_text", parsed.source_type
        assert_nil parsed.source_url
        assert_kind_of Hash, parsed.source_metadata
        assert_operator parsed.source_metadata["byte_size"], :>, 0

        assert_equal 1, parsed.commanders.size
        assert_equal "Atraxa, Praetors' Voice", parsed.commanders.first[:name]

        assert_equal 3, parsed.boards["main"].size
        assert_equal 3, parsed.main_card_count
        assert_equal 4, parsed.total_card_count
        assert_empty parsed.unparsed_lines
      end

      test "parse tolerates blank input" do
        parsed = Adapters::PastedText.new.parse("")
        assert_empty parsed.commanders
        assert_empty parsed.boards
      end
    end
  end
end
