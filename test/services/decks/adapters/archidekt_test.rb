require "test_helper"

module Decks
  module Adapters
    class ArchidektTest < ActiveSupport::TestCase
      SAMPLE_JSON = {
        "id" => 12345,
        "name" => "Atraxa Counters",
        "categories" => [
          { "name" => "Commander", "includedInDeck" => true, "isPremier" => true },
          { "name" => "Sideboard", "includedInDeck" => false, "isPremier" => false },
          { "name" => "Maybeboard", "includedInDeck" => false, "isPremier" => false },
          { "name" => "Considering", "includedInDeck" => false, "isPremier" => false }
        ],
        "cards" => [
          {
            "quantity" => 1,
            "categories" => [ "Commander" ],
            "card" => {
              "oracleCard" => { "name" => "Atraxa, Praetors' Voice" },
              "edition" => { "editioncode" => "CMR" },
              "collectorNumber" => "297"
            }
          },
          {
            "quantity" => 1,
            "categories" => [],
            "card" => {
              "oracleCard" => { "name" => "Sol Ring" },
              "edition" => { "editioncode" => "CMM" },
              "collectorNumber" => "410"
            }
          },
          {
            "quantity" => 1,
            "categories" => [],
            "card" => {
              "oracleCard" => { "name" => "Arcane Signet" },
              "edition" => { "editioncode" => "ELD" }
            }
          },
          {
            "quantity" => 1,
            "categories" => [ "Sideboard" ],
            "card" => {
              "oracleCard" => { "name" => "Cyclonic Rift" },
              "edition" => { "editioncode" => "MM3" }
            }
          },
          {
            "quantity" => 1,
            "categories" => [ "Maybeboard" ],
            "card" => {
              "oracleCard" => { "name" => "Smothering Tithe" },
              "edition" => { "editioncode" => "RNA" }
            }
          },
          {
            "quantity" => 1,
            "categories" => [ "Considering" ],
            "card" => {
              "oracleCard" => { "name" => "Rhystic Study" },
              "edition" => { "editioncode" => "PCY" }
            }
          }
        ]
      }.freeze

      class FakeClient
        attr_reader :calls

        def initialize(response: SAMPLE_JSON, error: nil)
          @response = response
          @error = error
          @calls = []
        end

        def fetch_deck(deck_id)
          @calls << deck_id
          raise @error if @error
          @response
        end
      end

      test "source_type is archidekt_url" do
        assert_equal "archidekt_url", Adapters::Archidekt.new(client: FakeClient.new).source_type
      end

      test "parse extracts deck id, fetches, and returns a structured ParsedDeck" do
        client = FakeClient.new
        adapter = Adapters::Archidekt.new(client: client)

        parsed = adapter.parse("https://archidekt.com/decks/12345/atraxa-build")

        assert_equal [ "12345" ], client.calls
        assert_equal "archidekt_url", parsed.source_type
        assert_equal "https://archidekt.com/decks/12345", parsed.source_url
        assert_equal "12345", parsed.source_metadata["archidekt_deck_id"]

        assert_equal "Atraxa Counters", parsed.name
        assert_equal 1, parsed.commanders.size
        assert_equal "Atraxa, Praetors' Voice", parsed.commanders.first[:name]
        assert_equal "cmr", parsed.commanders.first[:set]
        assert_equal "297", parsed.commanders.first[:collector_number]

        main_names = parsed.boards["main"].map { |c| c[:name] }
        assert_equal [ "Sol Ring", "Arcane Signet" ], main_names

        assert_equal [ "Cyclonic Rift" ], parsed.boards["sideboard"].map { |c| c[:name] }
        assert_equal [ "Smothering Tithe" ], parsed.boards["maybeboard"].map { |c| c[:name] }
        # "Considering" is includedInDeck:false and not Sideboard/Maybeboard, so it's dropped.
        refute parsed.boards.key?("considering"), "should not route excluded categories to a board"
      end

      test "parse accepts www.archidekt.com" do
        client = FakeClient.new
        parsed = Adapters::Archidekt.new(client: client).parse("https://www.archidekt.com/decks/9876")
        assert_equal [ "9876" ], client.calls
        assert_equal "https://archidekt.com/decks/9876", parsed.source_url
      end

      test "parse rejects empty URL" do
        adapter = Adapters::Archidekt.new(client: FakeClient.new)
        assert_raises(Adapters::Archidekt::InvalidUrl) { adapter.parse("") }
      end

      test "parse rejects non-Archidekt host" do
        adapter = Adapters::Archidekt.new(client: FakeClient.new)
        assert_raises(Adapters::Archidekt::InvalidUrl) do
          adapter.parse("https://moxfield.com/decks/abc123")
        end
      end

      test "parse rejects URLs without a numeric deck id" do
        adapter = Adapters::Archidekt.new(client: FakeClient.new)
        assert_raises(Adapters::Archidekt::InvalidUrl) do
          adapter.parse("https://archidekt.com/")
        end
      end

      test "parse rejects malformed URLs" do
        adapter = Adapters::Archidekt.new(client: FakeClient.new)
        assert_raises(Adapters::Archidekt::InvalidUrl) do
          adapter.parse("not a url at all")
        end
      end

      test "parse translates 404 from the client into FetchFailed" do
        client = FakeClient.new(error: ArchidektClient::NotFoundError.new("missing"))
        adapter = Adapters::Archidekt.new(client: client)
        error = assert_raises(Adapters::Archidekt::FetchFailed) do
          adapter.parse("https://archidekt.com/decks/12345")
        end
        assert_match(/not found/i, error.message)
      end

      test "parse translates rate limit into FetchFailed" do
        client = FakeClient.new(error: ArchidektClient::RateLimitedError.new("429"))
        adapter = Adapters::Archidekt.new(client: client)
        assert_raises(Adapters::Archidekt::FetchFailed) do
          adapter.parse("https://archidekt.com/decks/12345")
        end
      end

      test "parse skips zero-quantity entries and missing names" do
        json = {
          "id" => 1, "name" => "Tiny",
          "categories" => [ { "name" => "Commander", "includedInDeck" => true, "isPremier" => true } ],
          "cards" => [
            { "quantity" => 1, "categories" => [ "Commander" ], "card" => { "oracleCard" => { "name" => "Atraxa, Praetors' Voice" } } },
            { "quantity" => 0, "categories" => [], "card" => { "oracleCard" => { "name" => "Sol Ring" } } },
            { "quantity" => 1, "categories" => [], "card" => { "oracleCard" => { "name" => "" } } }
          ]
        }
        adapter = Adapters::Archidekt.new(client: FakeClient.new(response: json))
        parsed = adapter.parse("https://archidekt.com/decks/1")

        assert_equal 1, parsed.commanders.size
        assert_empty Array(parsed.boards["main"])
        assert_includes parsed.unparsed_lines.first.to_s, "missing name"
      end
    end
  end
end
