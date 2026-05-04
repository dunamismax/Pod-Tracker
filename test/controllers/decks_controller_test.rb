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

  test "requires authentication for index" do
    get decks_path
    assert_redirected_to new_session_path
  end

  test "requires authentication for new" do
    get new_deck_path
    assert_redirected_to new_session_path
  end

  test "renders the new form for an authenticated user" do
    sign_in_as(@user)
    get new_deck_path
    assert_response :success
    assert_select "form"
    assert_select "textarea[name='deck_import_form[decklist]']"
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

  test "imports an uploaded text file" do
    sign_in_as(@user)

    upload = fixture_text_file("atraxa.txt", DECKLIST)

    assert_difference -> { @user.decks.count } => 1,
                      -> { AuditEvent.where(event_name: "deck.imported").count } => 1 do
      post decks_path, params: {
        deck_import_form: { decklist_file: upload, name: "Uploaded Atraxa" }
      }
    end

    deck = @user.decks.order(:id).last
    assert_redirected_to deck_path(deck)
    assert_equal "Uploaded Atraxa", deck.name
    assert_equal "text_file", deck.source_type
    assert_equal "atraxa.txt", deck.import_metadata.dig("source_metadata", "filename")
  end

  test "rejects an uploaded file with an unsupported extension" do
    sign_in_as(@user)

    upload = fixture_text_file("deck.exe", DECKLIST, content_type: "application/octet-stream")

    assert_no_difference -> { Deck.count } do
      post decks_path, params: {
        deck_import_form: { decklist_file: upload }
      }
    end

    assert_response :unprocessable_entity
    assert_select "li", /Unsupported file extension/i
  end

  test "rejects a decklist that has no commander" do
    sign_in_as(@user)

    assert_no_difference -> { Deck.count } do
      post decks_path, params: {
        deck_import_form: { decklist: "1 Sol Ring\n1 Command Tower" }
      }
    end

    assert_response :unprocessable_entity
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

    def fixture_text_file(name, content, content_type: "text/plain")
      tempfile = Tempfile.new([ "deck", File.extname(name) ])
      tempfile.binmode
      tempfile.write(content)
      tempfile.rewind
      Rack::Test::UploadedFile.new(tempfile.path, content_type, original_filename: name)
    end

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
