require "test_helper"

class DecksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { @user = users(:one) }

  DECKLIST = <<~TXT.freeze
    Commander
    1 Atraxa, Praetors' Voice

    Mainboard
    1 Sol Ring
    1 Arcane Signet
    1 Command Tower
  TXT

  test "index filters decks by name search and bracket" do
    sign_in_as(@user)
    atraxa = create_deck_for(@user)
    najeela = @user.decks.create!(
      name: "Najeela 5C Tempo",
      format: "commander",
      status: "imported",
      visibility: "private",
      source_type: "pasted_text",
      commander_names: [ "Najeela, the Blade-Blossom" ],
      last_imported_at: Time.current
    )
    create_analysis_for(najeela)

    get decks_path(q: "Atraxa")
    assert_response :success
    assert_select "a", text: atraxa.name
    assert_select "a", text: najeela.name, count: 0

    get decks_path(bracket: "2")
    assert_response :success
    assert_select "a", text: najeela.name
    assert_select "a", text: atraxa.name, count: 0

    get decks_path(bracket: "5")
    assert_response :success
    assert_select "p", /No decks match those filters/
  end

  test "index renders the mobile bottom nav for authenticated users" do
    sign_in_as(@user)

    get decks_path
    assert_response :success
    assert_select "nav[aria-label=Primary] a[aria-current=page]", text: /Decks/
  end

  test "imports a pasted decklist" do
    sign_in_as(@user)

    assert_difference -> { @user.decks.count } => 1,
                      -> { AuditEvent.where(event_name: "deck.imported").count } => 1 do
      post decks_path, params: {
        deck_import_form: { decklist: DECKLIST, name: "Atraxa Test" }
      }
    end

    deck = @user.decks.order(:id).last
    assert_redirected_to deck_path(deck)
    assert_equal "Atraxa Test", deck.name
    assert_equal [ "Atraxa, Praetors' Voice" ], deck.commander_names
    assert_equal 3, deck.deck_cards.where(board: "main").sum(:quantity)

    audit = AuditEvent.where(event_name: "deck.imported").last
    assert_equal @user.id, audit.user_id
    assert_equal deck.id, audit.auditable_id
    assert_equal "Deck", audit.auditable_type
  end

  test "rejects an empty decklist" do
    sign_in_as(@user)

    assert_no_difference -> { Deck.count } do
      post decks_path, params: { deck_import_form: { decklist: "" } }
    end

    assert_response :unprocessable_entity
    assert_select "li", /required/i
  end

  test "shows the deck and surfaces unparsed lines" do
    sign_in_as(@user)
    deck = create_deck_for(@user, unparsed: [ "this line could not be parsed" ])

    get deck_path(deck)
    assert_response :success
    assert_select "h1", deck.name
    assert_select "ul", /this line could not be parsed/
  end

  test "shows recommendation ownership labels" do
    sign_in_as(@user)
    deck = create_deck_for(@user)
    ramp_tag = CardTag.find_or_create_by!(slug: "ramp") do |tag|
      tag.category = "role"
      tag.label = "Ramp"
    end
    oracle_card = OracleCard.create!(
      name: "Arcane Signet",
      normalized_name: ApplicationRecord.normalize_card_name("Arcane Signet"),
      scryfall_oracle_id: SecureRandom.uuid
    )
    CardTagAssignment.find_or_create_by!(card_tag: ramp_tag, card_name: "Arcane Signet") do |assignment|
      assignment.oracle_card = oracle_card
    end
    @user.collection_cards.create!(name: "Arcane Signet", oracle_card: oracle_card, quantity: 1)
    analysis_run = deck.analysis_runs.create!(
      user: @user,
      kind: "deterministic",
      status: "succeeded",
      rubric_version: Decks::Scorer::RUBRIC_VERSION,
      queued_at: Time.current,
      completed_at: Time.current
    )
    analysis_run.create_scorecard!(
      power_score: 3,
      speed_score: 3,
      interaction_score: 3,
      consistency_score: 3,
      salt_score: 0,
      social_friction_score: 0,
      confidence: 1.0,
      improvement_suggestions: [
        { "category" => "ramp", "title" => "Add ramp", "detail" => "Found 4 ramp pieces." }
      ]
    )

    get deck_path(deck)

    assert_response :success
    assert_select "span", /Owned options available/
    assert_select "span", /Arcane Signet/
  end

  test "destroys a deck and records an audit event" do
    sign_in_as(@user)
    deck = create_deck_for(@user)

    assert_difference -> { Deck.count } => -1,
                      -> { AuditEvent.where(event_name: "deck.removed").count } => 1 do
      delete deck_path(deck)
    end
    assert_redirected_to decks_path
  end

  test "queues an AI deck evaluation from the show page action" do
    sign_in_as(@user)
    connect_codex_account!
    deck = create_deck_for(@user)
    create_analysis_for(deck)
    clear_enqueued_jobs

    assert_difference -> { deck.analysis_runs.where(kind: "ai").count }, 1 do
      assert_enqueued_with(job: CodexEvaluationJob) do
        post deck_ai_evaluation_path(deck)
      end
    end

    assert_redirected_to deck_path(deck)
    assert_equal "queued", deck.latest_ai_run.status
  ensure
    clear_enqueued_jobs
  end

  test "cannot view another user's deck" do
    sign_in_as(@user)
    other_deck = create_deck_for(users(:two))

    get deck_path(other_deck)
    assert_response :not_found
  end

  private

    def create_deck_for(user, unparsed: [])
      deck = user.decks.create!(
        name: "Existing deck",
        format: "commander",
        status: "imported",
        visibility: "private",
        source_type: "pasted_text",
        commander_names: [ "Atraxa, Praetors' Voice" ],
        last_imported_at: Time.current,
        import_metadata: { "unparsed_lines" => unparsed }
      )
      deck.commanders.create!(name: "Atraxa, Praetors' Voice", position: 1)
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
        feature_vector: { "total_cards" => 2, "role_counts" => {}, "salt_counts" => {}, "friction_counts" => {} },
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

    def connect_codex_account!
      @user.codex_account&.destroy
      @user.create_codex_account!(
        auth_mode: Codex::AccountConnections::BROWSER_AUTH_MODE,
        status: "connected",
        encrypted_credential_payload: "opaque",
        rate_limit_snapshot: { "primary" => { "used" => 1, "limit" => 100 } },
        connected_at: Time.current
      )
    end
end
