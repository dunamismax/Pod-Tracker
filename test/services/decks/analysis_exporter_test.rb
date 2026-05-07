require "test_helper"

module Decks
  class AnalysisExporterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @deck = @user.decks.create!(
        name: "Najeela 5C",
        format: "commander",
        status: "imported",
        visibility: "private",
        source_type: "pasted_text",
        commander_names: [ "Najeela, the Blade-Blossom" ],
        last_imported_at: Time.utc(2026, 5, 1, 12)
      )
      @deck.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 1)
      @run = @deck.analysis_runs.create!(
        user: @user,
        kind: "deterministic",
        status: "succeeded",
        rubric_version: Decks::Scorer::RUBRIC_VERSION,
        queued_at: Time.utc(2026, 5, 1, 12),
        completed_at: Time.utc(2026, 5, 1, 12, 30),
        feature_vector: {},
        deterministic_snapshot: {
          "legality" => {
            "legal" => true,
            "snapshot_source" => "mtgcommander.net",
            "snapshot_effective_on" => "2026-02-09",
            "issues" => []
          }
        }
      )
      @run.create_scorecard!(
        power_score: 7,
        speed_score: 6,
        interaction_score: 5,
        consistency_score: 6,
        salt_score: 4,
        social_friction_score: 3,
        bracket: 4,
        bracket_sub_band: "mid",
        bracket_payload: {
          "headline" => "Bracket 4 — Optimized",
          "tagline" => "Cards optimized for the table.",
          "expected_min_turn" => 5,
          "game_changers" => [ { "name" => "Mana Drain", "category" => "interaction" } ],
          "combo_pairs" => [ { "name" => "Najeela infinite", "wins_immediately" => true } ],
          "restrictions" => [
            { "label" => "Mass land denial", "status" => "ok", "allowance" => "0", "actual" => "0", "evidence" => [] }
          ]
        },
        improvement_suggestions: [
          { "title" => "Add removal", "detail" => "Pack more interaction.", "ownership" => {} }
        ],
        confidence: 0.8
      )
    end

    test "to_h returns analysis payload with bracket and scores" do
      payload = AnalysisExporter.new(@deck, run: @run, generated_at: Time.utc(2026, 5, 7)).to_h

      assert_equal AnalysisExporter::SCHEMA_VERSION, payload[:schema_version]
      assert_equal "Najeela 5C", payload[:deck][:name]
      assert_equal 4, payload[:analysis][:bracket]
      assert_equal "mid", payload[:analysis][:bracket_sub_band]
      assert_equal 7, payload[:analysis][:scores][:power_score]
      assert_equal "Add removal", payload[:analysis][:improvement_suggestions].first["title"]
      assert payload[:analysis][:legality]["legal"]
    end

    test "to_h returns analysis: nil when no run is present" do
      empty_deck = @user.decks.create!(
        name: "Empty",
        format: "commander",
        status: "draft",
        visibility: "private",
        source_type: "pasted_text"
      )

      payload = AnalysisExporter.new(empty_deck).to_h
      assert_nil payload[:analysis]
    end

    test "to_markdown renders bracket headline, scores, and suggestions" do
      md = AnalysisExporter.new(@deck, run: @run, generated_at: Time.utc(2026, 5, 7)).to_markdown

      assert_includes md, "# Deterministic analysis — Najeela 5C"
      assert_includes md, "## Commander Bracket"
      assert_includes md, "Bracket 4 — Optimized"
      assert_includes md, "## Sub-band evidence — six-axis scorecard"
      assert_includes md, "| Power | 7/10 |"
      assert_includes md, "Mana Drain"
      assert_includes md, "Najeela infinite"
      assert_includes md, "## Suggestions"
      assert_includes md, "- **Add removal** — Pack more interaction."
    end

    test "to_markdown notes when analysis has not run" do
      empty_deck = @user.decks.create!(
        name: "Empty",
        format: "commander",
        status: "draft",
        visibility: "private",
        source_type: "pasted_text"
      )

      md = AnalysisExporter.new(empty_deck).to_markdown
      assert_includes md, "Deterministic analysis has not run for this deck yet."
    end

    test "filename includes deck slug and stamp" do
      filename = AnalysisExporter.new(@deck, run: @run, generated_at: Time.utc(2026, 5, 7, 9, 0)).filename("md")
      assert_equal "ideal-magic-analysis-najeela-5c-20260507T090000Z.md", filename
    end
  end
end
