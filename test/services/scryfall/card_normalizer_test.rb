require "test_helper"

module Scryfall
  class CardNormalizerTest < ActiveSupport::TestCase
    test "normalizes single-faced card facts for corpus lookup" do
      normalizer = CardNormalizer.new(scryfall_card(
        "name" => "Sol Ring",
        "mana_cost" => " {1} ",
        "cmc" => 1.0,
        "type_line" => " Artifact ",
        "oracle_text" => " {T}: Add {C}{C}. ",
        "colors" => [],
        "color_identity" => [],
        "produced_mana" => [ "C" ],
        "keywords" => [ "  ", "mana ability", "mana ability" ],
        "legalities" => { "commander" => "legal", "modern" => "not_legal" },
        "image_uris" => {
          "large" => " https://cards.scryfall.io/large/front/sol-ring.jpg ",
          "normal" => "https://cards.scryfall.io/normal/front/sol-ring.jpg"
        }
      ))

      oracle_attributes = normalizer.oracle_attributes
      printing_image_uris = normalizer.printing_image_uris

      assert_equal("{1}", oracle_attributes.fetch(:mana_cost))
      assert_equal(1.0, oracle_attributes.fetch(:mana_value))
      assert_equal("Artifact", oracle_attributes.fetch(:type_line))
      assert_equal("{T}: Add {C}{C}.", oracle_attributes.fetch(:oracle_text))
      assert_equal([ "C" ], oracle_attributes.fetch(:produced_mana))
      assert_equal([ "mana ability" ], oracle_attributes.fetch(:keywords))
      assert_equal({ "modern" => "not_legal", "commander" => "legal" }, oracle_attributes.fetch(:legalities))
      assert_equal("https://cards.scryfall.io/normal/front/sol-ring.jpg", printing_image_uris.fetch("normal"))
      assert_equal("https://cards.scryfall.io/large/front/sol-ring.jpg", printing_image_uris.fetch("large"))
    end

    test "normalizes multi-faced card faces and preserves face image uris" do
      normalizer = CardNormalizer.new(scryfall_card(
        "name" => "Wear // Tear",
        "layout" => "split",
        "mana_cost" => "{1}{R} // {W}",
        "cmc" => 3.0,
        "type_line" => "Instant // Instant",
        "colors" => [ "R", "W" ],
        "color_identity" => [ "R", "W" ],
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
      ))

      oracle_attributes = normalizer.oracle_attributes
      printing_image_uris = normalizer.printing_image_uris

      assert_equal([ "W", "R" ], oracle_attributes.fetch(:colors))
      assert_equal([ "W", "R" ], oracle_attributes.fetch(:color_identity))
      assert_equal(2, oracle_attributes.fetch(:faces).size)
      assert_equal("wear", oracle_attributes.fetch(:faces).first.fetch("normalized_name"))
      assert_equal("Destroy target enchantment.", oracle_attributes.fetch(:faces).second.fetch("oracle_text"))
      assert_equal("https://cards.scryfall.io/normal/front/wear.jpg", printing_image_uris.fetch("faces").first.fetch("image_uris").fetch("normal"))
      assert_equal("tear", printing_image_uris.fetch("faces").second.fetch("normalized_name"))
    end

    private

    def scryfall_card(attributes)
      {
        "object" => "card",
        "id" => SecureRandom.uuid,
        "oracle_id" => SecureRandom.uuid,
        "lang" => "en",
        "layout" => "normal",
        "set" => "cmm",
        "set_name" => "Commander Masters",
        "set_type" => "masters",
        "released_at" => "2023-08-04",
        "digital" => false,
        "rarity" => "uncommon",
        "collector_number" => "703",
        "image_status" => "highres_scan",
        "prices" => {},
        "purchase_uris" => {},
        "reserved" => false
      }.merge(attributes)
    end
  end
end
