require "test_helper"

class DeckAnalysisExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @deck = create_deck_for(@user)
    create_analysis_for(@deck)
  end

  test "downloads analysis as markdown" do
    sign_in_as(@user)

    get deck_analysis_export_path(@deck, format: :markdown)
    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_match(/pod-tracker-analysis-existing-deck-/, response.headers["Content-Disposition"])
    assert_includes response.body, "# Analysis — Existing deck"
    assert_includes response.body, "## Deterministic analysis"
    assert_includes response.body, "| Power |"
  end

  test "downloads analysis as json" do
    sign_in_as(@user)

    get deck_analysis_export_path(@deck, format: :json)
    assert_response :success
    parsed = JSON.parse(response.body)
    assert_equal "Existing deck", parsed["deck"]["name"]
    assert_equal 2, parsed["analysis"]["bracket"]
  end

  test "renders analysis-not-run note when no scorecard exists" do
    sign_in_as(@user)
    bare = @user.decks.create!(
      name: "Bare deck",
      format: "commander",
      status: "draft",
      visibility: "private",
      source_type: "pasted_text"
    )

    get deck_analysis_export_path(bare, format: :markdown)
    assert_response :success
    assert_includes response.body, "Analysis has not run for this deck yet."
  end

  private

    def create_deck_for(user)
      deck = user.decks.create!(
        name: "Existing deck",
        format: "commander",
        status: "imported",
        visibility: "private",
        source_type: "pasted_text",
        commander_names: [ "Atraxa, Praetors' Voice" ],
        last_imported_at: Time.current
      )
      deck.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 1)
      deck
    end

    def create_analysis_for(deck)
      run = deck.analysis_runs.create!(
        user: deck.user,
        kind: "deterministic",
        status: "succeeded",
        rubric_version: Decks::Scorer::RUBRIC_VERSION,
        queued_at: Time.current,
        completed_at: Time.current,
        feature_vector: {},
        deterministic_snapshot: { "legality" => { "legal" => true } }
      )
      run.create_scorecard!(
        power_score: 3,
        speed_score: 3,
        interaction_score: 3,
        consistency_score: 3,
        salt_score: 0,
        social_friction_score: 0,
        bracket: 2,
        bracket_sub_band: "low",
        bracket_payload: { "headline" => "Bracket 2", "game_changers" => [], "combo_pairs" => [] },
        confidence: 1.0
      )
      run
    end
end
