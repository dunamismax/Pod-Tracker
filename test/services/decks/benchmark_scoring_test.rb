require "test_helper"

module Decks
  class BenchmarkScoringTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      CommanderFormat::CardTagImporter.new.import!
      @library = FixtureLibrary.new
    end

    test "deterministic scoring separates the four benchmark power bands" do
      precon = analyze("precon_korlash_mono_black")
      casual = analyze("krenko_goblin_tribal")
      upgraded = analyze("atraxa_superfriends_upgraded")
      high_power = analyze("high_power_najeela_5c")

      assert_operator high_power.scorecard.power_score, :>, precon.scorecard.power_score,
        "high-power power must beat precon power"
      assert_operator high_power.scorecard.power_score, :>=, upgraded.scorecard.power_score,
        "high-power power must not fall below upgraded power"
      assert_operator upgraded.scorecard.power_score, :>=, casual.scorecard.power_score,
        "upgraded power must not fall below casual power"

      assert_operator high_power.scorecard.consistency_score, :>, precon.scorecard.consistency_score,
        "tutor + draw density should lift high-power consistency above precon"

      assert_operator high_power.scorecard.interaction_score, :>, casual.scorecard.interaction_score,
        "stack interaction + protection density should lift high-power interaction above casual"
      assert_operator upgraded.scorecard.interaction_score, :>, casual.scorecard.interaction_score,
        "upgraded should out-interact mono-red goblins"
    end

    test "salt and social-friction scores stay quiet for low/mid bands and rise meaningfully for high-power" do
      precon = analyze("precon_korlash_mono_black")
      casual_red = analyze("krenko_goblin_tribal")
      casual_green = analyze("mono_green_omnath_stompy")
      upgraded = analyze("atraxa_superfriends_upgraded")
      high_power = analyze("high_power_najeela_5c")

      assert_equal 0, precon.scorecard.salt_score, "precon contains no salt drivers"
      assert_equal 0, precon.scorecard.social_friction_score, "precon contains no friction drivers"
      assert_equal 0, casual_green.scorecard.salt_score, "mono-green stompy contains no salt drivers"
      assert_equal 0, casual_green.scorecard.social_friction_score
      assert_equal 0, upgraded.scorecard.salt_score, "upgraded fixture contains no salt drivers"
      assert_equal 0, upgraded.scorecard.social_friction_score, "upgraded fixture contains no friction drivers"

      # Krenko carries a single chaos driver (Chaos Warp); allow up to one salt point.
      assert_operator casual_red.scorecard.salt_score, :<=, 1
      assert_equal 0, casual_red.scorecard.social_friction_score

      assert_operator high_power.scorecard.salt_score, :>=, 5,
        "high-power deck should land in the high salt band"
      assert_operator high_power.scorecard.social_friction_score, :>=, 4,
        "high-power deck should produce meaningful Rule-0 friction"
      assert_operator high_power.scorecard.salt_score, :>, casual_red.scorecard.salt_score
    end

    test "feature counts reflect the band: tutors, fast mana, stax, and combo grow with power" do
      precon = features("precon_korlash_mono_black")
      upgraded = features("atraxa_superfriends_upgraded")
      high_power = features("high_power_najeela_5c")

      assert_equal 0, precon.role_counts.fetch("tutor"), "precon must have no curated tutors"
      assert_equal 0, precon.role_counts.fetch("combo"), "precon must have no combo pieces"
      assert_equal 0, precon.role_counts.fetch("stax"), "precon must have no stax pieces"

      assert_operator high_power.role_counts.fetch("tutor"), :>=, 6,
        "high-power deck must run a real tutor suite"
      assert_operator high_power.role_counts.fetch("fast_mana"), :>=, 5,
        "high-power deck must run a fast-mana stack"
      assert_operator high_power.role_counts.fetch("stax"), :>=, 3,
        "high-power deck must run stax pressure"
      assert_operator high_power.role_counts.fetch("combo"), :>=, 3,
        "high-power deck must run a compact combo line"

      assert_operator high_power.role_counts.fetch("tutor"), :>, upgraded.role_counts.fetch("tutor")
      assert_operator high_power.role_counts.fetch("fast_mana"), :>, upgraded.role_counts.fetch("fast_mana")
    end

    test "benchmark fixtures land in the expected Commander Brackets" do
      assert_equal 2, analyze("precon_korlash_mono_black").scorecard.bracket,
        "a precon-shaped deck with no GCs should land in Bracket 2 (Core)"
      assert_equal 2, analyze("krenko_goblin_tribal").scorecard.bracket,
        "a casual goblin deck without GCs should land in Bracket 2"
      assert_equal 2, analyze("mono_green_omnath_stompy").scorecard.bracket,
        "casual stompy without GCs should land in Bracket 2"

      upgraded = analyze("atraxa_superfriends_upgraded").scorecard
      assert_includes [ 3, 4 ], upgraded.bracket,
        "upgraded fixtures should land in Bracket 3 (or 4 if they pile on GCs)"

      high_power = analyze("high_power_najeela_5c").scorecard
      assert_includes [ 4, 5 ], high_power.bracket,
        "high-power Najeela should land in Bracket 4 or 5"

      cedh = analyze("cedh_tymna_thrasios_thoracle").scorecard
      assert_equal 5, cedh.bracket,
        "Tymna + Thrasios cEDH with the Thoracle/Consultation line, GC stack, fast-mana, and tutor density should land in Bracket 5"
      assert_equal "cEDH", cedh.bracket_payload["label"]
      assert cedh.bracket_payload["game_changers"].size >= 6,
        "cEDH fixture should expose >=6 Game Changers in the bracket payload"
      combo_pairs = cedh.bracket_payload["combo_pairs"]
      assert combo_pairs.any? { |p| p["wins_immediately"] },
        "cEDH fixture should detect at least one immediate-win two-card combo"
    end

    test "every benchmark fixture yields a scorecard whose values stay within 0..10" do
      %w[precon_korlash_mono_black krenko_goblin_tribal mono_green_omnath_stompy
         atraxa_superfriends_upgraded high_power_najeela_5c
         cedh_tymna_thrasios_thoracle].each do |slug|
        run = analyze(slug)
        scorecard = run.scorecard
        %i[power_score speed_score interaction_score consistency_score salt_score social_friction_score].each do |field|
          assert_includes 0..10, scorecard.public_send(field),
            "#{slug} produced an out-of-range #{field}: #{scorecard.public_send(field)}"
        end
      end
    end

    private

    def analyze(slug)
      deck = @library.build_deck(slug, user: @user)
      assert deck.save, "expected fixture #{slug} to save: #{deck.errors.full_messages.inspect}"
      Analyzer.run(deck)
    end

    def features(slug)
      deck = @library.build_deck(slug, user: @user)
      assert deck.save, "expected fixture #{slug} to save: #{deck.errors.full_messages.inspect}"
      FeatureExtractor.new.call(deck.reload)
    end
  end
end
