require "test_helper"

module Decks
  class BracketEvaluatorTest < ActiveSupport::TestCase
    def features(role_counts: {}, salt_counts: {}, evidence_by_tag: {})
      role_defaults = FeatureExtractor::ROLE_TAG_SLUGS.index_with { |_| 0 }
      salt_defaults = FeatureExtractor::SALT_TAG_SLUGS.index_with { |_| 0 }
      friction_defaults = FeatureExtractor::FRICTION_TAG_SLUGS.index_with { |_| 0 }
      curve = FeatureExtractor::MANA_CURVE_BUCKETS.each_with_object({}) { |b, h| h[b.to_s] = 0 }
      FeatureExtractor::Result.new(
        total_cards: 100, nonland_count: 64, land_count: 36, mana_source_count: 40,
        role_counts: role_defaults.merge(role_counts),
        salt_counts: salt_defaults.merge(salt_counts),
        friction_counts: friction_defaults,
        mana_curve: curve, color_pip_counts: { "W" => 0, "U" => 0, "B" => 0, "R" => 0, "G" => 0, "C" => 0 },
        commander_color_identity: [],
        evidence_by_tag: evidence_by_tag,
        missing_oracle_count: 0
      )
    end

    test "a theme deck with no GCs, no MLD, no extra turns, no combos lands in Bracket 1" do
      f = features(role_counts: { "card_draw" => 4, "ramp" => 6 })
      result = BracketEvaluator.new.call(features: f, card_names: %w[Forest Mountain Plains], scorecard: nil)
      assert_equal 1, result.bracket
      assert_equal "Exhibition", result.label
      assert_equal 9, result.expected_min_turn
    end

    test "a casual deck with one splashy extra turn lands in Bracket 2" do
      f = features(
        role_counts: { "card_draw" => 8, "removal" => 6, "ramp" => 8 },
        salt_counts: { "salt_driver_extra_turns" => 1 },
        evidence_by_tag: { "salt_driver_extra_turns" => [ "Time Warp" ] }
      )
      result = BracketEvaluator.new.call(features: f, card_names: [ "Time Warp", "Sol Ring" ], scorecard: nil)
      assert_equal 2, result.bracket
      assert_equal "Core", result.label
    end

    test "1 to 3 Game Changers pushes a deck into Bracket 3" do
      f = features(role_counts: { "tutor" => 2, "card_draw" => 8, "removal" => 6 })
      result = BracketEvaluator.new.call(
        features: f,
        card_names: [ "Rhystic Study", "Smothering Tithe", "Sol Ring" ],
        scorecard: nil
      )
      assert_equal 3, result.bracket
      assert_equal 2, result.evidence["game_changer_count"]
    end

    test "more than 3 Game Changers pushes the deck into Bracket 4" do
      f = features(role_counts: { "tutor" => 4, "fast_mana" => 3, "combo" => 2 })
      result = BracketEvaluator.new.call(
        features: f,
        card_names: [ "Rhystic Study", "Smothering Tithe", "Mana Vault", "Demonic Tutor", "Vampiric Tutor", "Mystical Tutor" ],
        scorecard: nil
      )
      assert_equal 4, result.bracket
    end

    test "mass land denial pushes a deck out of Brackets 1-3 even with no Game Changers" do
      f = features(
        role_counts: { "ramp" => 8 },
        salt_counts: { "salt_driver_mass_land_denial" => 1 },
        evidence_by_tag: { "salt_driver_mass_land_denial" => [ "Armageddon" ] }
      )
      result = BracketEvaluator.new.call(features: f, card_names: [ "Armageddon" ], scorecard: nil)
      assert_equal 4, result.bracket
      mld = result.restrictions.find { |r| r["key"] == "mass_land_denial" }
      assert_equal "present_allowed", mld["status"]
    end

    test "chained extra turns force the deck up to Bracket 4" do
      f = features(
        role_counts: { "card_draw" => 8 },
        salt_counts: { "salt_driver_extra_turns" => 4 },
        evidence_by_tag: { "salt_driver_extra_turns" => [ "Time Warp", "Time Stretch", "Temporal Manipulation", "Walk the Aeons" ] }
      )
      result = BracketEvaluator.new.call(features: f, card_names: [ "Time Warp", "Time Stretch", "Temporal Manipulation", "Walk the Aeons" ], scorecard: nil)
      assert_equal 4, result.bracket
    end

    test "an immediate-win two-card combo pushes the deck into Bracket 4 even with no GCs" do
      f = features(role_counts: { "combo" => 2, "tutor" => 1 })
      result = BracketEvaluator.new.call(
        features: f,
        card_names: [ "Thassa's Oracle", "Demonic Consultation" ],
        scorecard: nil
      )
      assert_equal 4, result.bracket
      pair = result.combo_pairs.first
      assert_equal "Thassa's Oracle + Demonic Consultation", pair["name"]
      assert pair["wins_immediately"]
    end

    test "a cEDH-shaped deck with deep tutor + fast mana + combo lands in Bracket 5" do
      f = features(
        role_counts: { "tutor" => 6, "fast_mana" => 5, "combo" => 4, "stack_interaction" => 6, "card_draw" => 12 }
      )
      result = BracketEvaluator.new.call(
        features: f,
        card_names: [
          "Demonic Tutor", "Vampiric Tutor", "Mystical Tutor", "Imperial Seal", "Worldly Tutor", "Enlightened Tutor",
          "Mana Vault", "Mana Crypt", "Chrome Mox", "Mox Diamond", "Lion's Eye Diamond", "Ancient Tomb",
          "Force of Will", "Fierce Guardianship",
          "Thassa's Oracle", "Demonic Consultation"
        ],
        scorecard: nil
      )
      assert_equal 5, result.bracket
      assert_equal "cEDH", result.label
    end

    test "result hash exposes all the fields the deck show page reads" do
      f = features(role_counts: { "card_draw" => 4 })
      h = BracketEvaluator.new.call(features: f, card_names: %w[Forest], scorecard: nil).to_h
      %w[bracket label tagline sub_band expected_min_turn game_changers restrictions combo_pairs evidence headline version].each do |key|
        assert h.key?(key), "expected bracket payload to expose #{key}"
      end
    end

    test "headline string mentions Game Changers and combos when present" do
      f = features(role_counts: { "tutor" => 2, "combo" => 2 })
      result = BracketEvaluator.new.call(
        features: f,
        card_names: [ "Rhystic Study", "Thassa's Oracle", "Demonic Consultation" ],
        scorecard: Struct.new(:power_score, :speed_score).new(8, 7)
      )
      assert_includes result.headline, "Bracket"
      assert_includes result.headline, "Game Changer"
    end
  end
end
