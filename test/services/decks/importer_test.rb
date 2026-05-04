require "test_helper"

module Decks
  class ImporterTest < ActiveSupport::TestCase
    setup { @user = users(:one) }

    DECKLIST_WITH_HEADER = <<~TXT.freeze
      Commander
      1 Atraxa, Praetors' Voice

      Mainboard
      1 Sol Ring
      1 Arcane Signet
      1 Command Tower
    TXT

    DECKLIST_WITHOUT_COMMANDER = <<~TXT.freeze
      1 Sol Ring
      1 Arcane Signet
      1 Command Tower
    TXT

    test "imports a pasted decklist with a Commander header" do
      result = Importer.import_pasted_text(user: @user, payload: DECKLIST_WITH_HEADER)

      assert result.success?, result.error_messages.inspect
      assert result.deck.persisted?
      assert_equal "pasted_text", result.deck.source_type
      assert_equal [ "Atraxa, Praetors' Voice" ], result.deck.commander_names
      assert_equal 3, result.deck.deck_cards.where(board: "main").sum(:quantity)
      assert_equal 1, result.deck.commanders.count
      assert_equal "imported", result.deck.status
      assert_equal "private", result.deck.visibility
      assert_equal "commander", result.deck.format
      assert_equal @user, result.deck.user
      assert_equal "pasted_text", result.deck.import_metadata["source_type"]
      assert result.deck.last_imported_at.present?
    end

    test "uses commander_hint when no Commander header is present" do
      result = Importer.import_pasted_text(
        user: @user,
        payload: DECKLIST_WITHOUT_COMMANDER,
        commander_hint: "Atraxa, Praetors' Voice"
      )

      assert result.success?, result.error_messages.inspect
      assert_equal [ "Atraxa, Praetors' Voice" ], result.deck.commander_names
      assert_equal 1, result.deck.commanders.count
    end

    test "rejects an empty decklist" do
      result = Importer.import_pasted_text(user: @user, payload: "")
      refute result.success?
      assert_nil result.deck
      assert_includes result.error_messages.join(" "), "empty"
    end

    test "rejects a decklist with no commander hint and no header" do
      result = Importer.import_pasted_text(user: @user, payload: DECKLIST_WITHOUT_COMMANDER)
      refute result.success?
      assert_includes result.error_messages.join(" "), "commander"
    end

    test "uses supplied name when provided" do
      result = Importer.import_pasted_text(
        user: @user,
        payload: DECKLIST_WITH_HEADER,
        name: "  My Atraxa Brew  "
      )
      assert result.success?, result.error_messages.inspect
      assert_equal "My Atraxa Brew", result.deck.name
    end

    test "derives the deck name from the commander when blank" do
      result = Importer.import_pasted_text(user: @user, payload: DECKLIST_WITH_HEADER)
      assert_equal "Atraxa, Praetors' Voice", result.deck.name
    end

    test "records unparsed lines in import_metadata" do
      decklist = "Commander\n1 Atraxa, Praetors' Voice\nMainboard\n1 Sol Ring\nnot a card line"
      result = Importer.import_pasted_text(user: @user, payload: decklist)

      assert result.success?, result.error_messages.inspect
      assert_includes result.deck.import_metadata["unparsed_lines"], "not a card line"
    end

    test "imports an uploaded text file" do
      file = uploaded_file(DECKLIST_WITH_HEADER, filename: "atraxa.txt", content_type: "text/plain")
      result = Importer.import_text_file(user: @user, file: file)

      assert result.success?, result.error_messages.inspect
      assert_equal "text_file", result.deck.source_type
      assert_equal "atraxa.txt", result.deck.import_metadata.dig("source_metadata", "filename")
      assert_equal [ "Atraxa, Praetors' Voice" ], result.deck.commander_names
      assert_equal 3, result.deck.deck_cards.where(board: "main").sum(:quantity)
    end

    test "import_text_file surfaces invalid file errors" do
      file = uploaded_file("not a decklist", filename: "deck.exe", content_type: "application/octet-stream")
      result = Importer.import_text_file(user: @user, file: file)

      refute result.success?
      assert_nil result.deck
      assert_includes result.error_messages.join(" "), "Unsupported file extension"
    end

    test "imports an Archidekt deck URL with a fake client" do
      adapter = Adapters::Archidekt.new(client: stub_archidekt_client)

      result = Importer.import_archidekt_url(
        user: @user,
        url: "https://archidekt.com/decks/12345/atraxa-stuff",
        adapter: adapter
      )

      assert result.success?, result.error_messages.inspect
      assert_equal "archidekt_url", result.deck.source_type
      assert_equal "Atraxa Sample", result.deck.name
      assert_equal [ "Atraxa, Praetors' Voice" ], result.deck.commander_names
      assert_equal "https://archidekt.com/decks/12345", result.deck.import_metadata["source_url"]
      assert_equal "12345", result.deck.import_metadata.dig("source_metadata", "archidekt_deck_id")
      assert_equal 2, result.deck.deck_cards.where(board: "main").sum(:quantity)
    end

    test "import_archidekt_url surfaces invalid URLs" do
      adapter = Adapters::Archidekt.new(client: stub_archidekt_client)
      result = Importer.import_archidekt_url(
        user: @user,
        url: "https://moxfield.com/decks/abc",
        adapter: adapter
      )
      refute result.success?
      assert_nil result.deck
      assert_includes result.error_messages.join(" "), "Archidekt"
    end

    test "import_archidekt_url surfaces fetch failures" do
      client = Class.new do
        def fetch_deck(_id) = raise Decks::ArchidektClient::NotFoundError, "missing"
      end.new
      adapter = Adapters::Archidekt.new(client: client)
      result = Importer.import_archidekt_url(
        user: @user,
        url: "https://archidekt.com/decks/12345",
        adapter: adapter
      )
      refute result.success?
      assert_includes result.error_messages.join(" ").downcase, "not found"
    end

    test "imports a Moxfield deck URL with a fake client" do
      adapter = Adapters::Moxfield.new(client: stub_moxfield_client)

      result = Importer.import_moxfield_url(
        user: @user,
        url: "https://www.moxfield.com/decks/Bq8YrKpmnEKQTd-ZHBHQXg",
        adapter: adapter
      )

      assert result.success?, result.error_messages.inspect
      assert_equal "moxfield_url", result.deck.source_type
      assert_equal "Atraxa Moxfield Sample", result.deck.name
      assert_equal [ "Atraxa, Praetors' Voice" ], result.deck.commander_names
      assert_equal "https://www.moxfield.com/decks/Bq8YrKpmnEKQTd-ZHBHQXg", result.deck.import_metadata["source_url"]
      assert_equal "Bq8YrKpmnEKQTd-ZHBHQXg", result.deck.import_metadata.dig("source_metadata", "moxfield_deck_id")
      assert_equal 2, result.deck.deck_cards.where(board: "main").sum(:quantity)
    end

    test "import_moxfield_url surfaces invalid URLs" do
      adapter = Adapters::Moxfield.new(client: stub_moxfield_client)
      result = Importer.import_moxfield_url(
        user: @user,
        url: "https://archidekt.com/decks/abc",
        adapter: adapter
      )
      refute result.success?
      assert_nil result.deck
      assert_includes result.error_messages.join(" "), "Moxfield"
    end

    test "import_moxfield_url surfaces fetch failures" do
      client = Class.new do
        def fetch_deck(_slug) = raise Decks::MoxfieldClient::NotFoundError, "missing"
      end.new
      adapter = Adapters::Moxfield.new(client: client)
      result = Importer.import_moxfield_url(
        user: @user,
        url: "https://www.moxfield.com/decks/abc",
        adapter: adapter
      )
      refute result.success?
      assert_includes result.error_messages.join(" ").downcase, "not found"
    end

    private

    def stub_moxfield_client
      json = {
        "name" => "Atraxa Moxfield Sample",
        "boards" => {
          "commanders" => {
            "cards" => {
              "atraxa" => { "quantity" => 1, "card" => { "name" => "Atraxa, Praetors' Voice" } }
            }
          },
          "mainboard" => {
            "cards" => {
              "sol" => { "quantity" => 1, "card" => { "name" => "Sol Ring" } },
              "signet" => { "quantity" => 1, "card" => { "name" => "Arcane Signet" } }
            }
          }
        }
      }
      Class.new do
        define_method(:fetch_deck) { |_slug| json }
      end.new
    end


    def stub_archidekt_client
      json = {
        "id" => 12345,
        "name" => "Atraxa Sample",
        "categories" => [
          { "name" => "Commander", "includedInDeck" => true, "isPremier" => true }
        ],
        "cards" => [
          { "quantity" => 1, "categories" => [ "Commander" ],
            "card" => { "oracleCard" => { "name" => "Atraxa, Praetors' Voice" } } },
          { "quantity" => 1, "categories" => [],
            "card" => { "oracleCard" => { "name" => "Sol Ring" } } },
          { "quantity" => 1, "categories" => [],
            "card" => { "oracleCard" => { "name" => "Arcane Signet" } } }
        ]
      }
      Class.new do
        define_method(:fetch_deck) { |_id| json }
      end.new
    end


    def uploaded_file(content, filename:, content_type: "text/plain")
      tempfile = Tempfile.new([ "deck", File.extname(filename) ])
      tempfile.binmode
      tempfile.write(content)
      tempfile.rewind
      ActionDispatch::Http::UploadedFile.new(
        tempfile: tempfile,
        filename: filename,
        type: content_type
      )
    end
  end
end
