require "test_helper"

module Decks
  class FeatureExtractorTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)

      @ramp_tag = CardTag.find_or_create_by!(slug: "ramp") do |t|
        t.label = "Ramp"
        t.category = "role"
      end
      @fast_mana_tag = CardTag.find_or_create_by!(slug: "fast_mana") do |t|
        t.label = "Fast mana"
        t.category = "role"
      end
      @salt_fast_mana_tag = CardTag.find_or_create_by!(slug: "salt_driver_fast_mana") do |t|
        t.label = "Salt: fast mana"
        t.category = "salt"
        t.default_severity = "moderate"
      end
      @friction_combo_tag = CardTag.find_or_create_by!(slug: "social_friction_combo_opacity") do |t|
        t.label = "Friction: combo"
        t.category = "social_friction"
      end

      assign_tag(@ramp_tag, "Sol Ring")
      assign_tag(@fast_mana_tag, "Sol Ring")
      assign_tag(@salt_fast_mana_tag, "Sol Ring")
      assign_tag(@ramp_tag, "Arcane Signet")
      assign_tag(@friction_combo_tag, "Demonic Consultation")
    end

    test "counts roles, lands, mana sources, and curve buckets from a small deck" do
      sol_ring = OracleCard.create!(
        scryfall_oracle_id: SecureRandom.uuid, name: "Sol Ring",
        type_line: "Artifact", mana_cost: "{1}", mana_value: 1,
        color_identity: [], colors: []
      )
      arcane_signet = OracleCard.create!(
        scryfall_oracle_id: SecureRandom.uuid, name: "Arcane Signet",
        type_line: "Artifact", mana_cost: "{2}", mana_value: 2,
        color_identity: [], colors: []
      )
      consultation = OracleCard.create!(
        scryfall_oracle_id: SecureRandom.uuid, name: "Demonic Consultation",
        type_line: "Instant", mana_cost: "{B}", mana_value: 1,
        color_identity: %w[B], colors: %w[B]
      )
      atraxa = OracleCard.create!(
        scryfall_oracle_id: SecureRandom.uuid, name: "Atraxa, Praetors' Voice",
        type_line: "Legendary Creature - Phyrexian Angel Horror",
        mana_cost: "{G}{W}{U}{B}", mana_value: 4,
        color_identity: %w[B G U W], colors: %w[B G U W]
      )

      deck = Deck.create!(
        user: @user, name: "Tiny Atraxa",
        format: "commander", status: "imported", visibility: "private"
      )
      deck.commanders.create!(name: "Atraxa, Praetors' Voice", position: 1, oracle_card: atraxa)
      deck.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 1, oracle_card: sol_ring)
      deck.deck_cards.create!(name: "Arcane Signet", quantity: 1, board: "main", position: 2, oracle_card: arcane_signet)
      deck.deck_cards.create!(name: "Demonic Consultation", quantity: 1, board: "main", position: 3, oracle_card: consultation)
      deck.deck_cards.create!(name: "Swamp", quantity: 30, board: "main", position: 4)
      deck.deck_cards.create!(name: "Forest", quantity: 30, board: "main", position: 5)
      deck.deck_cards.create!(name: "Atraxa, Praetors' Voice", quantity: 1, board: "commander", position: 1, oracle_card: atraxa)

      result = FeatureExtractor.new.call(deck.reload)

      assert_equal 64, result.total_cards
      assert_equal 60, result.land_count
      assert_equal 4, result.nonland_count
      assert_equal 63, result.mana_source_count, "lands plus ramp + fast_mana (Sol Ring tagged twice)"

      assert_equal 2, result.role_counts["ramp"], "Sol Ring + Arcane Signet"
      assert_equal 1, result.role_counts["fast_mana"], "Sol Ring"
      assert_equal 1, result.salt_counts["salt_driver_fast_mana"], "Sol Ring"
      assert_equal 1, result.friction_counts["social_friction_combo_opacity"]

      assert_equal 2, result.mana_curve["1"], "Sol Ring + Demonic Consultation at MV 1"
      assert_includes result.evidence_by_tag["ramp"], "Sol Ring"
      assert_includes result.evidence_by_tag["salt_driver_fast_mana"], "Sol Ring"
    end

    test "treats tagless basic lands as lands and surfaces missing_oracle_count" do
      deck = Deck.create!(
        user: @user, name: "Bare Lands",
        format: "commander", status: "imported", visibility: "private"
      )
      deck.commanders.create!(name: "Atraxa, Praetors' Voice", position: 1)
      deck.deck_cards.create!(name: "Plains", quantity: 30, board: "main", position: 1)
      deck.deck_cards.create!(name: "Snow-Covered Forest", quantity: 30, board: "main", position: 2)
      deck.deck_cards.create!(name: "Some Unknown Card", quantity: 5, board: "main", position: 3)

      result = FeatureExtractor.new.call(deck.reload)

      assert_equal 65, result.total_cards
      assert_equal 60, result.land_count, "basic + snow-covered basic counted as lands"
      assert_operator result.missing_oracle_count, :>=, 5
    end

    private

    def assign_tag(tag, name)
      CardTagAssignment.find_or_create_by!(
        card_tag: tag,
        normalized_card_name: ApplicationRecord.normalize_card_name(name)
      ) do |row|
        row.card_name = name
        row.source = "curated"
      end
    end
  end
end
