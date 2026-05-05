require "test_helper"

module Decks
  class ScorerTest < ActiveSupport::TestCase
    test "scores a healthy mid-power deck within reasonable bands" do
      features = build_features(
        role_counts: {
          "ramp" => 8, "fast_mana" => 1, "tutor" => 1, "card_draw" => 9,
          "protection" => 2, "removal" => 8, "stack_interaction" => 0,
          "board_wipe" => 2, "stax" => 0, "combo" => 0, "graveyard_use" => 1,
          "land" => 36, "win_condition" => 1
        },
        land_count: 36,
        mana_source_count: 45,
        mana_curve: { "0" => 1, "1" => 4, "2" => 12, "3" => 18, "4" => 14, "5" => 8, "6" => 9 },
        total_cards: 100
      )

      result = Scorer.new(severity_lookup: {}).call(features)

      assert_equal "deterministic-v0", result.rubric_version
      assert_includes 3..7, result.scores["power"].value, "power should be midband"
      assert_includes 3..7, result.scores["interaction"].value
      assert_operator result.scores["consistency"].value, :>=, 4
      assert_equal 0, result.scores["salt"].value
      assert_equal 0, result.scores["social_friction"].value
      assert_empty result.recommendations
    end

    test "punishes a thin manabase and missing draw with reduced consistency and a recommendation" do
      features = build_features(
        role_counts: { "ramp" => 4, "card_draw" => 3, "removal" => 4, "land" => 30 },
        land_count: 30,
        mana_source_count: 34,
        mana_curve: { "0" => 0, "1" => 2, "2" => 6, "3" => 12, "4" => 14, "5" => 12, "6" => 24 },
        total_cards: 100
      )

      result = Scorer.new(severity_lookup: {}).call(features)

      assert_operator result.scores["consistency"].value, :<=, 4
      assert_operator result.scores["speed"].value, :<=, 4

      categories = result.recommendations.map { |r| r["category"] }
      assert_includes categories, "lands"
      assert_includes categories, "draw"
      assert_includes categories, "mana"
    end

    test "salt score tracks weighted salt drivers and surfaces them as evidence" do
      features = build_features(
        salt_counts: {
          "salt_driver_fast_mana" => 2,
          "salt_driver_mass_land_denial" => 1,
          "salt_driver_extra_turns" => 0
        },
        evidence_by_tag: {
          "salt_driver_fast_mana" => [ "Mana Crypt", "Mana Vault" ],
          "salt_driver_mass_land_denial" => [ "Armageddon" ]
        }
      )

      result = Scorer.new(severity_lookup: {
        "salt_driver_fast_mana" => "moderate",
        "salt_driver_mass_land_denial" => "high"
      }).call(features)

      salt = result.scores["salt"]
      assert_operator salt.value, :>=, 2

      driver_tags = Array(salt.evidence["drivers"]).map { |d| d["tag"] }
      assert_includes driver_tags, "salt_driver_fast_mana"
      assert_includes driver_tags, "salt_driver_mass_land_denial"

      mld = salt.evidence["drivers"].find { |d| d["tag"] == "salt_driver_mass_land_denial" }
      assert_equal "Armageddon", Array(mld["cards"]).first
    end

    test "social_friction score includes combo and stax base contributions" do
      features = build_features(
        friction_counts: { "social_friction_combo_opacity" => 2 },
        role_counts: { "combo" => 4, "stax" => 2 },
        evidence_by_tag: {
          "social_friction_combo_opacity" => [ "Thassa's Oracle", "Demonic Consultation" ]
        }
      )

      result = Scorer.new(severity_lookup: {}).call(features)

      friction = result.scores["social_friction"]
      assert_operator friction.value, :>=, 2
      driver_tags = Array(friction.evidence["drivers"]).map { |d| d["tag"] }
      assert_includes driver_tags, "social_friction_combo_opacity"
    end

    test "score values stay within the 0..10 range for an empty deck" do
      features = build_features(total_cards: 0)
      result = Scorer.new(severity_lookup: {}).call(features)
      result.scores.each_value do |score|
        assert_includes 0..10, score.value, "expected #{score.value} to be within 0..10"
      end
    end

    private

    def build_features(role_counts: {}, salt_counts: {}, friction_counts: {}, evidence_by_tag: {},
                      mana_curve: {}, color_pip_counts: {}, land_count: 0, mana_source_count: 0,
                      total_cards: 100, missing_oracle_count: 0)
      role_defaults = FeatureExtractor::ROLE_TAG_SLUGS.index_with { |_| 0 }
      salt_defaults = FeatureExtractor::SALT_TAG_SLUGS.index_with { |_| 0 }
      friction_defaults = FeatureExtractor::FRICTION_TAG_SLUGS.index_with { |_| 0 }
      curve_defaults = FeatureExtractor::MANA_CURVE_BUCKETS.each_with_object({}) { |b, h| h[b.to_s] = 0 }

      FeatureExtractor::Result.new(
        total_cards: total_cards,
        nonland_count: [ total_cards - land_count, 0 ].max,
        land_count: land_count,
        mana_source_count: mana_source_count,
        role_counts: role_defaults.merge(role_counts),
        salt_counts: salt_defaults.merge(salt_counts),
        friction_counts: friction_defaults.merge(friction_counts),
        mana_curve: curve_defaults.merge(mana_curve),
        color_pip_counts: { "W" => 0, "U" => 0, "B" => 0, "R" => 0, "G" => 0, "C" => 0 }.merge(color_pip_counts),
        commander_color_identity: [],
        evidence_by_tag: evidence_by_tag,
        missing_oracle_count: missing_oracle_count
      )
    end
  end
end
