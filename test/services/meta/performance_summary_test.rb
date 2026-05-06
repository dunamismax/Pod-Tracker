require "test_helper"

module Meta
  class PerformanceSummaryTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @deck = @user.decks.create!(
        name: "Krenko Goblins",
        commander_names: [ "Krenko, Mob Boss" ]
      )
      @deck.deck_cards.create!(name: "Skirk Prospector", quantity: 1, board: "main", position: 1)
      @other_deck = @user.decks.create!(
        name: "Omnath Stompy",
        commander_names: [ "Omnath, Locus of Mana" ]
      )
      @pilot = @user.players.create!(name: "Mara")
      @opponent = @user.players.create!(name: "Stephen")
    end

    test "summarizes deck performance and revision snapshots from completed pods" do
      create_analysis_for(@deck, completed_at: Time.zone.local(2026, 5, 1, 18), power_score: 40)
      create_completed_pod(played_on: Date.new(2026, 5, 1), winner: @pilot, turns: 4)

      @deck.update!(name: "Krenko Goblins v2")
      create_analysis_for(@deck, completed_at: Time.zone.local(2026, 5, 2, 18), power_score: 48)
      create_completed_pod(played_on: Date.new(2026, 5, 2), winner: nil, draw: true, turns: 8)

      summary = PerformanceSummary.for_user(@user)
      performance = summary.deck_performance(@deck)
      revisions = summary.revision_performance(@deck)

      assert_equal 2, performance.games
      assert_equal 1, performance.wins
      assert_equal 1, performance.draws
      assert_equal 0, performance.losses
      assert_in_delta 0.5, performance.win_rate
      assert_in_delta 6.0, performance.average_turns
      assert_equal "thin sample", performance.confidence_label
      assert_equal 2, revisions.size
      assert_equal [ 1, 1 ], revisions.map { |revision| revision.stats.games }
    end

    test "summarizes commander meta with visible sample-size language" do
      create_completed_pod(played_on: Date.new(2026, 5, 1), winner: @pilot, turns: 7)
      create_completed_pod(played_on: Date.new(2026, 5, 2), winner: @opponent, turns: 9)

      commander = PerformanceSummary.for_user(@user).commander_meta.find { |line| line.name == "Krenko, Mob Boss" }

      assert_not_nil commander
      assert_equal 2, commander.games
      assert_equal 1, commander.wins
      assert_in_delta 0.5, commander.win_rate
      assert_equal "thin sample", commander.confidence_label
      assert_equal "sample too thin", commander.trend_label
    end

    test "builds post-game prompts for outcomes, short games, dead draws, and missing cards" do
      game_night = create_completed_pod(played_on: Date.new(2026, 5, 1), winner: @pilot, turns: 4)

      prompt = PerformanceSummary.for_user(@user).post_game_prompts(game_night).find { |line| line.deck == @deck }

      assert_equal "win", prompt.outcome
      assert prompt.prompts.any? { |line| line.include?("caused this win") }
      assert prompt.prompts.any? { |line| line.include?("dead draws") }
      assert prompt.prompts.any? { |line| line.include?("turn 4") }
      assert prompt.prompts.any? { |line| line.include?("Skirk Prospector") }
    end

    private
      def create_completed_pod(played_on:, winner:, turns:, draw: false)
        game_night = @user.game_nights.create!(
          name: "Friday Commander #{played_on}",
          played_on: played_on,
          status: "completed"
        )
        game_night.game_night_pod_seats.create!(
          player: @pilot,
          deck: @deck,
          pod_number: 1,
          seat_number: 1
        )
        game_night.game_night_pod_seats.create!(
          player: @opponent,
          deck: @other_deck,
          pod_number: 1,
          seat_number: 2
        )
        game_night.game_night_pod_results.create!(
          pod_number: 1,
          winner_player: winner,
          draw: draw,
          turns: turns,
          win_condition: draw ? nil : "Combat damage"
        )
        game_night
      end

      def create_analysis_for(deck, completed_at:, power_score:)
        run = deck.analysis_runs.create!(
          user: @user,
          kind: "deterministic",
          status: "succeeded",
          rubric_version: "test",
          queued_at: completed_at,
          completed_at: completed_at
        )
        run.create_scorecard!(
          bracket: 2,
          bracket_sub_band: "mid",
          power_score: power_score,
          speed_score: 40,
          interaction_score: 30,
          consistency_score: 30,
          salt_score: 20,
          social_friction_score: 20,
          confidence: 1.0
        )
        run
      end
  end
end
