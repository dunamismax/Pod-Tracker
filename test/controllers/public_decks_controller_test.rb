require "test_helper"

class PublicDecksControllerTest < ActionDispatch::IntegrationTest
  setup do
    CommanderFormat::CardTagImporter.new.import!
    @user = users(:one)
    library = Decks::FixtureLibrary.new
    @deck = library.build_deck("krenko_goblin_tribal", user: @user)
    @deck.save!
    Decks::Analyzer.run(@deck)
    @deck.issue_share_token!
  end

  test "show renders shared deck with deterministic analysis for an anonymous visitor" do
    get public_deck_path(@deck.share_token)
    assert_response :success
    assert_match(/Shared Commander deck/, response.body)
    assert_match(/#{Regexp.escape(@deck.name)}/, response.body)
    assert_match(/Deterministic analysis/, response.body)
  end

  test "show surfaces the AI evaluation as authoritative when a successful AI run exists" do
    payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
    @deck.analysis_runs.create!(
      user: @user,
      kind: "ai",
      status: "succeeded",
      rubric_version: Codex::DeckEvaluationSchema::VERSION,
      prompt_version: Codex::DeckEvaluationPrompt::PROMPT_VERSION,
      ai_model: "test-model",
      queued_at: Time.current,
      started_at: Time.current,
      completed_at: Time.current,
      ai_response_snapshot: { "validated_response" => payload }
    )

    get public_deck_path(@deck.share_token)
    assert_response :success
    assert_match(/AI deck evaluation/, response.body)
    assert_match(/Show preliminary deterministic read/, response.body)
  end

  test "show renders without analysis when none exists" do
    bare = @user.decks.create!(
      name: "Bare deck",
      format: "commander",
      status: "imported",
      visibility: "private",
      source_type: "pasted_text"
    )
    bare.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 1)
    bare.issue_share_token!

    get public_deck_path(bare.share_token)
    assert_response :success
    assert_match(/Deterministic analysis has not run/, response.body)
  end

  test "show 404s for an unknown token" do
    get public_deck_path("not-a-token")
    assert_response :not_found
  end

  test "show 404s after revocation" do
    @deck.revoke_share!
    get public_deck_path(@deck.share_token)
    assert_response :not_found
  end

  test "show does not leak matchup notes, table performance, or collection data" do
    @deck.matchup_notes.create!(user: @user, body: "PRIVATE_PLAYGROUP_NOTE", happened_at: Time.current, tags: [])

    get public_deck_path(@deck.share_token)
    assert_response :success
    refute_match(/PRIVATE_PLAYGROUP_NOTE/, response.body)
    refute_match(/Table performance/, response.body)
    refute_match(/Collection fit/, response.body)
  end

  test "export downloads decklist text via share token" do
    get public_deck_export_path(@deck.share_token, format: :text)
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match(/^attachment;/, response.headers["Content-Disposition"])
  end

  test "export downloads decklist json via share token" do
    get public_deck_export_path(@deck.share_token, format: :json)
    assert_response :success
    parsed = JSON.parse(response.body)
    assert_equal @deck.name, parsed["deck"]["name"]
  end

  test "export 404s after revocation" do
    @deck.revoke_share!
    get public_deck_export_path(@deck.share_token, format: :text)
    assert_response :not_found
  end

  test "analysis downloads markdown via share token" do
    get public_deck_analysis_path(@deck.share_token, format: :markdown)
    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_match(/Deterministic analysis/, response.body)
  end

  test "analysis markdown includes AI evaluation when present" do
    payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
    @deck.analysis_runs.create!(
      user: @user,
      kind: "ai",
      status: "succeeded",
      rubric_version: Codex::DeckEvaluationSchema::VERSION,
      prompt_version: Codex::DeckEvaluationPrompt::PROMPT_VERSION,
      ai_model: "test-model",
      queued_at: Time.current,
      started_at: Time.current,
      completed_at: Time.current,
      ai_response_snapshot: { "validated_response" => payload }
    )

    get public_deck_analysis_path(@deck.share_token, format: :markdown)
    assert_response :success
    assert_match(/AI evaluation \(Commander Brackets\)/, response.body)
  end

  test "analysis json includes ai_evaluation block when present" do
    payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
    @deck.analysis_runs.create!(
      user: @user,
      kind: "ai",
      status: "succeeded",
      rubric_version: Codex::DeckEvaluationSchema::VERSION,
      prompt_version: Codex::DeckEvaluationPrompt::PROMPT_VERSION,
      ai_model: "test-model",
      queued_at: Time.current,
      started_at: Time.current,
      completed_at: Time.current,
      ai_response_snapshot: { "validated_response" => payload }
    )

    get public_deck_analysis_path(@deck.share_token, format: :json)
    assert_response :success
    parsed = JSON.parse(response.body)
    assert parsed["ai_evaluation"].present?
    assert parsed["ai_evaluation"]["authoritative"]
  end

  test "analysis downloads json via share token" do
    get public_deck_analysis_path(@deck.share_token, format: :json)
    assert_response :success
    parsed = JSON.parse(response.body)
    assert_equal @deck.name, parsed["deck"]["name"]
    assert parsed["analysis"].present?
  end

  test "analysis 404s after revocation" do
    @deck.revoke_share!
    get public_deck_analysis_path(@deck.share_token, format: :json)
    assert_response :not_found
  end
end
