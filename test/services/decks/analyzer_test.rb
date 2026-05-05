require "test_helper"

module Decks
  class AnalyzerTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @snapshot = LegalitySnapshot.find_or_create_by!(
        source: "mtgcommander", format: "commander", effective_on: Date.new(2024, 9, 23)
      )
    end

    test "persists an AnalysisRun, Scorecard, and feature_vector for a small legal deck" do
      atraxa = OracleCard.create!(
        scryfall_oracle_id: SecureRandom.uuid, name: "Atraxa, Praetors' Voice",
        type_line: "Legendary Creature - Phyrexian Angel Horror",
        mana_cost: "{G}{W}{U}{B}", mana_value: 4,
        color_identity: %w[B G U W], colors: %w[B G U W]
      )

      deck = Deck.create!(
        user: @user, name: "Atraxa Tiny",
        format: "commander", status: "imported", visibility: "private"
      )
      deck.commanders.create!(name: "Atraxa, Praetors' Voice", position: 1, oracle_card: atraxa)
      deck.deck_cards.create!(name: "Atraxa, Praetors' Voice", quantity: 1, board: "commander", position: 1, oracle_card: atraxa)
      deck.deck_cards.create!(name: "Plains", quantity: 99, board: "main", position: 1)

      run = Analyzer.run(deck)

      assert_equal "deterministic", run.kind
      assert_equal "succeeded", run.status
      assert run.completed_at.present?
      assert run.feature_vector.present?
      assert_equal 100, run.feature_vector["total_cards"]
      assert_equal 99, run.feature_vector["land_count"]

      scorecard = run.scorecard
      assert_not_nil scorecard
      assert_includes 0..10, scorecard.power_score
      assert_includes 0..10, scorecard.salt_score
      assert_includes 0..10, scorecard.social_friction_score
      assert_in_delta 1.0, scorecard.confidence.to_f, 0.01
      assert_kind_of Array, scorecard.improvement_suggestions

      legality_payload = run.deterministic_snapshot["legality"]
      assert_not_nil legality_payload
      assert_includes [ true, false ], legality_payload["legal"]
    end

    test "rolls back on error so partial AnalysisRun rows are not left behind" do
      deck = Deck.create!(
        user: @user, name: "Will Fail",
        format: "commander", status: "imported", visibility: "private"
      )
      deck.commanders.create!(name: "Atraxa, Praetors' Voice", position: 1)
      deck.deck_cards.create!(name: "Plains", quantity: 99, board: "main", position: 1)

      Scorecard.singleton_class.alias_method(:original_create!, :create!)
      Scorecard.define_singleton_method(:create!) { |*_args, **_kwargs| raise "boom" }
      begin
        assert_raises(RuntimeError) { Analyzer.run(deck) }
      ensure
        Scorecard.singleton_class.alias_method(:create!, :original_create!)
        Scorecard.singleton_class.send(:remove_method, :original_create!)
      end

      assert_equal 0, deck.analysis_runs.reload.count
    end
  end
end
