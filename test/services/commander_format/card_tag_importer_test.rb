require "test_helper"

module CommanderFormat
  class CardTagImporterTest < ActiveSupport::TestCase
    test "imports the source-controlled card tag taxonomy and curated overrides" do
      result = CardTagImporter.new.import!

      slugs = result.tags.map(&:slug)
      assert_includes slugs, "ramp"
      assert_includes slugs, "fast_mana"
      assert_includes slugs, "tutor"
      assert_includes slugs, "card_draw"
      assert_includes slugs, "protection"
      assert_includes slugs, "removal"
      assert_includes slugs, "stack_interaction"
      assert_includes slugs, "board_wipe"
      assert_includes slugs, "stax"
      assert_includes slugs, "combo"
      assert_includes slugs, "graveyard_use"
      assert_includes slugs, "land"
      assert_includes slugs, "win_condition"
      assert_includes slugs, "salt_driver_mass_land_denial"
      assert_includes slugs, "social_friction_disclosure_required"

      mass_land_denial = CardTag.find_by!(slug: "salt_driver_mass_land_denial")
      assert_equal "salt", mass_land_denial.category
      assert_equal 12.0, mass_land_denial.salt_weight
      assert_equal "high", mass_land_denial.default_severity

      friction = CardTag.find_by!(slug: "social_friction_disclosure_required")
      assert_equal "social_friction", friction.category
      assert_equal 6.0, friction.friction_weight

      armageddon = CardTagAssignment.for_card_name("Armageddon").to_a
      armageddon_slugs = armageddon.map { |assignment| assignment.card_tag.slug }
      assert_includes armageddon_slugs, "salt_driver_mass_land_denial"
      assert_includes armageddon_slugs, "social_friction_disclosure_required"

      assert_predicate result.assignments.size, :positive?
    end

    test "is idempotent when run multiple times" do
      importer = CardTagImporter.new
      importer.import!
      tag_count = CardTag.count
      assignment_count = CardTagAssignment.count

      importer.import!

      assert_equal tag_count, CardTag.count
      assert_equal assignment_count, CardTagAssignment.count
    end

    test "links assignments to oracle cards when they already exist" do
      OracleCard.create!(
        scryfall_oracle_id: SecureRandom.uuid,
        name: "Mana Crypt"
      )

      CardTagImporter.new.import!

      mana_crypt_assignments = CardTagAssignment.for_card_name("Mana Crypt")
      assert mana_crypt_assignments.any?
      assert mana_crypt_assignments.all? { |assignment| assignment.oracle_card.present? }
    end
  end
end
