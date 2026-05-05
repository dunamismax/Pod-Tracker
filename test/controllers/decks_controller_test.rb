require "test_helper"

class DecksControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  DECKLIST = <<~TXT.freeze
    Commander
    1 Atraxa, Praetors' Voice

    Mainboard
    1 Sol Ring
    1 Arcane Signet
    1 Command Tower
  TXT

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

  test "destroys a deck and records an audit event" do
    sign_in_as(@user)
    deck = create_deck_for(@user)

    assert_difference -> { Deck.count } => -1,
                      -> { AuditEvent.where(event_name: "deck.removed").count } => 1 do
      delete deck_path(deck)
    end
    assert_redirected_to decks_path
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
end
