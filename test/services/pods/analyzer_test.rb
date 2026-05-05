require "test_helper"

module Pods
  class AnalyzerTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      CommanderFormat::CardTagImporter.new.import!
      @library = Decks::FixtureLibrary.new
    end

    test "mismatched four-deck pod produces archenemy + salt-mismatch warnings and a Rule 0 brief" do
      pod = build_pod_from_fixtures(
        "Friday mismatched",
        %w[precon_korlash_mono_black krenko_goblin_tribal atraxa_superfriends_upgraded high_power_najeela_5c]
      )

      run = Pods::Analyzer.run(pod, user: @user)

      assert_equal "succeeded", run.status
      assert_equal "analyzed", pod.reload.status

      snapshot = run.snapshot
      assert_equal 4, Array(snapshot["slots"]).size

      power_aggregate = snapshot.dig("aggregates", "power")
      assert power_aggregate["spread"] >= 2, "expected wide power spread, got #{power_aggregate.inspect}"
      assert_equal 4, power_aggregate["values"].size

      kinds = run.warnings.map { |w| w["kind"] }
      assert_includes kinds, "archenemy_risk"
      assert_includes kinds, "salt_mismatch"

      brief = run.rule_zero_brief
      assert brief.dig("power_band", "label").present?
      assert brief.dig("speed", "average").present?
      assert_kind_of Array, brief["combo_stax_notes"]
      assert_kind_of Array, brief["salt_notes"]

      suggestions = run.suggestions
      assert suggestions.any?, "expected at least one suggestion for mismatched pod"
      categories = suggestions.map { |s| s["category"] }
      assert_includes categories, "power_down"
    end

    test "balanced casual pod without salt drivers produces no archenemy or salt-mismatch warning" do
      pod = build_pod_from_fixtures(
        "Casual three-pod",
        %w[krenko_goblin_tribal mono_green_omnath_stompy precon_korlash_mono_black]
      )

      run = Pods::Analyzer.run(pod, user: @user)

      kinds = run.warnings.map { |w| w["kind"] }
      assert_not_includes kinds, "archenemy_risk"
      assert_not_includes kinds, "pubstomp_risk"

      power_aggregate = run.snapshot.dig("aggregates", "power")
      assert power_aggregate["max"] - power_aggregate["min"] < 3
    end

    test "mismatched-bracket pod produces a bracket spread aggregate and a bracket_mismatch warning" do
      pod = build_pod_from_fixtures(
        "Bracket-mismatched four-pod",
        %w[precon_korlash_mono_black mono_green_omnath_stompy atraxa_superfriends_upgraded cedh_tymna_thrasios_thoracle]
      )

      run = Pods::Analyzer.run(pod, user: @user)

      bracket = run.snapshot["bracket"]
      assert bracket, "expected bracket aggregate to be present"
      assert_operator bracket["spread"], :>=, 2,
        "expected bracket spread of at least 2 across precon → cEDH, got #{bracket.inspect}"
      assert_equal 2, bracket["min"]
      assert_equal 5, bracket["max"]
      assert_includes bracket["headline"], "Mixed pod"
      assert_includes bracket["distinct"], 5
      assert_operator bracket["game_changer_total"].to_i, :>=, 6,
        "cEDH slot alone should push the pod GC total well above 6"

      warnings = run.warnings
      kinds = warnings.map { |w| w["kind"] }
      assert_includes kinds, "bracket_mismatch",
        "expected a bracket_mismatch warning across a Bracket 2 → Bracket 5 spread"

      mismatch = warnings.find { |w| w["kind"] == "bracket_mismatch" }
      assert_includes mismatch["message"], "Bracket spread"
      assert_equal "alert", mismatch["severity"]
      hot_names = Array(mismatch["decks"]).map { |d| d["deck_name"] }
      assert_includes hot_names, "Tymna + Thrasios cEDH (Thoracle Consultation)"

      brief = run.rule_zero_brief
      assert_match(/Brackets 2.+5/, brief.dig("bracket", "label").to_s)
      template = brief["pregame_template"]
      assert_match(/Brackets 2/, template.first.to_s) if template.is_a?(Array) && template.any?
    end

    test "balanced single-bracket pod produces a single-bracket headline and no bracket_mismatch warning" do
      pod = build_pod_from_fixtures(
        "Balanced bracket-2 three-pod",
        %w[precon_korlash_mono_black mono_green_omnath_stompy krenko_goblin_tribal]
      )

      run = Pods::Analyzer.run(pod, user: @user)

      bracket = run.snapshot["bracket"]
      assert bracket
      assert_equal 0, bracket["spread"], "balanced pod should have a bracket spread of zero"
      assert_equal bracket["min"], bracket["max"]
      assert_equal 2, bracket["min"]
      assert_equal [ 2 ], bracket["distinct"]
      assert_match(/Bracket 2/, bracket["headline"])

      kinds = run.warnings.map { |w| w["kind"] }
      assert_not_includes kinds, "bracket_mismatch"

      brief = run.rule_zero_brief
      headline = brief.dig("bracket", "label")
      assert_match(/Bracket 2/, headline.to_s)
      assert_no_match(/Mixed/i, headline.to_s)
    end

    test "rejects pods with fewer than the minimum slot count" do
      pod = Pod.create!(user: @user, name: "Solo", format: "commander", status: "draft")
      assert_raises(ArgumentError) { Pods::Analyzer.run(pod, user: @user) }
    end

    test "runs deterministic deck analysis on the fly when a slot's deck has no scorecard" do
      deck = @library.build_deck("krenko_goblin_tribal", user: @user)
      deck.save!
      other = @library.build_deck("mono_green_omnath_stompy", user: @user)
      other.save!

      assert_nil deck.latest_deterministic_run, "expected new fixture deck to start without analysis"

      pod = Pod.create!(user: @user, name: "Auto-analyze", format: "commander", status: "draft")
      pod.pod_slots.create!(deck: deck, position: 1)
      pod.pod_slots.create!(deck: other, position: 2)

      run = Pods::Analyzer.run(pod, user: @user)

      slots = Array(run.snapshot["slots"])
      assert_equal 2, slots.size
      slots.each do |slot|
        assert slot["scores"], "expected each slot to receive scorecard scores"
      end
      assert deck.reload.latest_deterministic_run.present?
    end

    private

    def build_pod_from_fixtures(name, slugs)
      decks = slugs.map do |slug|
        deck = @library.build_deck(slug, user: @user)
        deck.save!
        Decks::Analyzer.run(deck)
        deck
      end

      pod = Pod.create!(user: @user, name: name, format: "commander", status: "draft")
      decks.each_with_index do |deck, idx|
        pod.pod_slots.create!(deck: deck, position: idx + 1)
      end
      pod
    end
  end
end
