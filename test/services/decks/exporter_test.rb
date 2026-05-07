require "test_helper"

module Decks
  class ExporterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @deck = @user.decks.create!(
        name: "Atraxa Test",
        format: "commander",
        status: "imported",
        visibility: "private",
        source_type: "pasted_text",
        commander_names: [ "Atraxa, Praetors' Voice" ],
        last_imported_at: Time.utc(2026, 5, 1, 12)
      )
      @deck.commanders.create!(name: "Atraxa, Praetors' Voice", position: 1)
      @deck.deck_cards.create!(name: "Atraxa, Praetors' Voice", quantity: 1, board: "commander", position: 1)
      @deck.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 1)
      @deck.deck_cards.create!(name: "Arcane Signet", quantity: 1, board: "main", position: 2)
    end

    test "to_text emits boards with quantity-prefixed lines" do
      text = Exporter.new(@deck, generated_at: Time.utc(2026, 5, 1, 12)).to_text

      assert_includes text, "# Atraxa Test"
      assert_includes text, "# Commander: Atraxa, Praetors' Voice"
      assert_includes text, "Commander\n1 Atraxa, Praetors' Voice"
      assert_includes text, "Mainboard\n1 Sol Ring\n1 Arcane Signet"
    end

    test "to_csv emits one row per card with board, quantity, name" do
      csv = Exporter.new(@deck).to_csv
      rows = CSV.parse(csv)

      assert_equal %w[board quantity name], rows.first
      assert_includes rows, [ "commander", "1", "Atraxa, Praetors' Voice" ]
      assert_includes rows, [ "main", "1", "Sol Ring" ]
    end

    test "to_h serializes boards and metadata" do
      payload = Exporter.new(@deck).to_h

      assert_equal Exporter::SCHEMA_VERSION, payload[:schema_version]
      assert_equal "Atraxa Test", payload[:deck][:name]
      assert_equal 3, payload[:deck][:card_count]
      assert_includes payload[:deck][:boards].keys, "main"
      main = payload[:deck][:boards]["main"]
      assert_equal 2, main.size
      assert_equal({ name: "Sol Ring", quantity: 1 }, main.first)
    end

    test "to_json round-trips through JSON.parse" do
      json = Exporter.new(@deck).to_json
      parsed = JSON.parse(json)

      assert_equal "Atraxa Test", parsed["deck"]["name"]
    end

    test "filename slugs the deck name and timestamps" do
      generated_at = Time.utc(2026, 5, 7, 9, 0, 0)
      filename = Exporter.new(@deck, generated_at: generated_at).filename("txt")
      assert_equal "ideal-magic-deck-atraxa-test-20260507T090000Z.txt", filename
    end
  end
end
