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
