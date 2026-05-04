require "test_helper"
require "stringio"

module Scryfall
  class BulkImporterTest < ActiveSupport::TestCase
    test "imports default card bulk data into card corpus records and stores refresh metadata" do
      bulk_object = {
        "type" => "default_cards",
        "download_uri" => "https://data.scryfall.io/default-cards/example.json",
        "content_type" => "application/json",
        "size" => 1_234,
        "updated_at" => "2026-05-04T09:08:19.941+00:00"
      }
      oracle_id = SecureRandom.uuid
      set_id = SecureRandom.uuid
      sol_ring = scryfall_card(
        "id" => SecureRandom.uuid,
        "oracle_id" => oracle_id,
        "set_id" => set_id,
        "name" => "Sol Ring",
        "mana_cost" => "{1}",
        "cmc" => 1.0,
        "type_line" => "Artifact",
        "oracle_text" => "{T}: Add {C}{C}.",
        "colors" => [],
        "color_identity" => [],
        "collector_number" => "703",
        "image_uris" => { "normal" => "https://cards.scryfall.io/normal/front/example.jpg" },
        "legalities" => { "commander" => "legal" },
        "keywords" => []
      )
      command_tower = scryfall_card(
        "id" => SecureRandom.uuid,
        "oracle_id" => SecureRandom.uuid,
        "set_id" => set_id,
        "name" => "Command Tower",
        "cmc" => 0.0,
        "type_line" => "Land",
        "oracle_text" => "{T}: Add one mana of any color in your commander's color identity.",
        "color_identity" => [],
        "collector_number" => "350",
        "legalities" => { "commander" => "legal" },
        "produced_mana" => %w[W U B R G]
      )

      refresh = BulkImporter.new.import!(
        bulk_type: "default_cards",
        source_io: StringIO.new([ sol_ring, command_tower ].to_json),
        bulk_object: bulk_object
      )

      assert_equal("succeeded", refresh.status)
      assert_equal("scryfall", refresh.source)
      assert_equal("default_cards", refresh.bulk_type)
      assert_equal(2, refresh.object_count)
      assert_equal(1, refresh.card_set_count)
      assert_equal(2, refresh.oracle_card_count)
      assert_equal(2, refresh.card_printing_count)
      assert_equal(Time.zone.parse("2026-05-04T09:08:19.941+00:00"), refresh.scryfall_updated_at)

      set = CardSet.find_by!(code: "cmm")
      oracle = OracleCard.find_by!(scryfall_oracle_id: oracle_id)
      printing = CardPrinting.find_by!(name: "Sol Ring")

      assert_equal(set_id, set.scryfall_id)
      assert_equal("Commander Masters", set.name)
      assert_equal("sol ring", oracle.normalized_name)
      assert_equal("{1}", oracle.mana_cost)
      assert_equal(1.0, oracle.mana_value)
      assert_equal("{T}: Add {C}{C}.", oracle.oracle_text)
      assert_equal({ "commander" => "legal" }, oracle.legalities)
      assert_equal(set, printing.card_set)
      assert_equal(oracle, printing.oracle_card)
      assert_equal("703", printing.collector_number)
      assert_equal("https://cards.scryfall.io/normal/front/example.jpg", printing.image_uris.fetch("normal"))
    end

    test "imports normalized multi-faced card facts and face image uris" do
      bulk_object = {
        "type" => "default_cards",
        "download_uri" => "https://data.scryfall.io/default-cards/faces.json"
      }
      split_card = scryfall_card(
        "id" => SecureRandom.uuid,
        "oracle_id" => SecureRandom.uuid,
        "set_id" => SecureRandom.uuid,
        "name" => "Wear // Tear",
        "layout" => "split",
        "mana_cost" => "{1}{R} // {W}",
        "cmc" => 3.0,
        "type_line" => "Instant // Instant",
        "colors" => [ "R", "W" ],
        "color_identity" => [ "R", "W" ],
        "collector_number" => "229",
        "legalities" => { "legacy" => "legal", "commander" => "legal" },
        "card_faces" => [
          {
            "name" => "Wear",
            "mana_cost" => "{1}{R}",
            "type_line" => "Instant",
            "oracle_text" => "Destroy target artifact.",
            "colors" => [ "R" ],
            "image_uris" => { "normal" => "https://cards.scryfall.io/normal/front/wear.jpg" }
          },
          {
            "name" => "Tear",
            "mana_cost" => "{W}",
            "type_line" => "Instant",
            "oracle_text" => "Destroy target enchantment.",
            "colors" => [ "W" ],
            "image_uris" => { "normal" => "https://cards.scryfall.io/normal/front/tear.jpg" }
          }
        ]
      )

      BulkImporter.new.import!(
        source_io: StringIO.new([ split_card ].to_json),
        bulk_object: bulk_object
      )

      oracle = OracleCard.find_by!(name: "Wear // Tear")
      printing = CardPrinting.find_by!(name: "Wear // Tear")

      assert_equal([ "W", "R" ], oracle.colors)
      assert_equal([ "W", "R" ], oracle.color_identity)
      assert_equal("wear", oracle.faces.first.fetch("normalized_name"))
      assert_equal("Destroy target enchantment.", oracle.faces.second.fetch("oracle_text"))
      assert_equal("https://cards.scryfall.io/normal/front/wear.jpg", printing.image_uris.fetch("faces").first.fetch("image_uris").fetch("normal"))
    end

    test "marks refresh failed when an import object is invalid" do
      bulk_object = {
        "type" => "default_cards",
        "download_uri" => "https://data.scryfall.io/default-cards/bad.json"
      }

      assert_raises(KeyError) do
        BulkImporter.new.import!(
          source_io: StringIO.new([ { "object" => "card", "id" => SecureRandom.uuid } ].to_json),
          bulk_object: bulk_object
        )
      end

      refresh = CardCorpusRefresh.order(:created_at).last
      assert_equal("failed", refresh.status)
      assert_equal("KeyError", refresh.error_code)
      assert_match(/key not found/, refresh.error_message)
    end

    private

    def scryfall_card(attributes)
      {
        "object" => "card",
        "lang" => "en",
        "layout" => "normal",
        "set" => "cmm",
        "set_name" => "Commander Masters",
        "set_type" => "masters",
        "released_at" => "2023-08-04",
        "digital" => false,
        "rarity" => "uncommon",
        "image_status" => "highres_scan",
        "prices" => { "usd" => "1.00" },
        "purchase_uris" => { "tcgplayer" => "https://example.com" },
        "reserved" => false
      }.merge(attributes)
    end
  end
end
