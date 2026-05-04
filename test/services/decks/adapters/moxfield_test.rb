require "test_helper"

module Decks
  module Adapters
    class MoxfieldTest < ActiveSupport::TestCase
      SAMPLE_JSON = {
        "name" => "Atraxa Moxfield",
        "boards" => {
          "commanders" => {
            "count" => 1,
            "cards" => {
              "atraxa" => {
                "quantity" => 1,
                "card" => { "name" => "Atraxa, Praetors' Voice", "set" => "CMR", "cn" => "297" }
              }
            }
          },
          "mainboard" => {
            "count" => 2,
            "cards" => {
              "sol" => {
                "quantity" => 1,
                "card" => { "name" => "Sol Ring", "set" => "CMM", "cn" => "410" }
              },
              "signet" => {
                "quantity" => 1,
                "card" => { "name" => "Arcane Signet", "set" => "ELD" }
              }
            }
          },
          "sideboard" => {
            "count" => 1,
            "cards" => {
              "rift" => {
                "quantity" => 1,
                "card" => { "name" => "Cyclonic Rift", "set" => "MM3" }
              }
            }
          },
          "maybeboard" => {
            "count" => 1,
            "cards" => {
              "tithe" => {
                "quantity" => 1,
                "card" => { "name" => "Smothering Tithe", "set" => "RNA" }
              }
            }
          },
          "considering" => {
            "count" => 1,
            "cards" => {
              "rhystic" => {
                "quantity" => 1,
                "card" => { "name" => "Rhystic Study", "set" => "PCY" }
              }
            }
          }
        }
      }.freeze

      class FakeClient
        attr_reader :calls

        def initialize(response: SAMPLE_JSON, error: nil)
          @response = response
          @error = error
          @calls = []
        end

        def fetch_deck(slug)
          @calls << slug
          raise @error if @error
          @response
        end
      end

      test "source_type is moxfield_url" do
        assert_equal "moxfield_url", Adapters::Moxfield.new(client: FakeClient.new).source_type
      end

      test "parse extracts deck slug, fetches, and returns a structured ParsedDeck" do
        client = FakeClient.new
        adapter = Adapters::Moxfield.new(client: client)

        parsed = adapter.parse("https://www.moxfield.com/decks/Bq8YrKpmnEKQTd-ZHBHQXg")

        assert_equal [ "Bq8YrKpmnEKQTd-ZHBHQXg" ], client.calls
        assert_equal "moxfield_url", parsed.source_type
        assert_equal "https://www.moxfield.com/decks/Bq8YrKpmnEKQTd-ZHBHQXg", parsed.source_url
        assert_equal "Bq8YrKpmnEKQTd-ZHBHQXg", parsed.source_metadata["moxfield_deck_id"]

        assert_equal "Atraxa Moxfield", parsed.name
        assert_equal 1, parsed.commanders.size
        assert_equal "Atraxa, Praetors' Voice", parsed.commanders.first[:name]
        assert_equal "cmr", parsed.commanders.first[:set]
        assert_equal "297", parsed.commanders.first[:collector_number]

        main_names = parsed.boards["main"].map { |c| c[:name] }.sort
        assert_equal [ "Arcane Signet", "Sol Ring" ], main_names

        assert_equal [ "Cyclonic Rift" ], parsed.boards["sideboard"].map { |c| c[:name] }
        assert_equal [ "Smothering Tithe" ], parsed.boards["maybeboard"].map { |c| c[:name] }
        refute parsed.boards.key?("considering"), "should not route unknown boards"
      end

      test "parse accepts moxfield.com without www" do
        client = FakeClient.new
        parsed = Adapters::Moxfield.new(client: client).parse("https://moxfield.com/decks/abcDEF123_-x")
        assert_equal [ "abcDEF123_-x" ], client.calls
        assert_equal "https://www.moxfield.com/decks/abcDEF123_-x", parsed.source_url
      end

      test "parse rejects empty URL" do
        adapter = Adapters::Moxfield.new(client: FakeClient.new)
        assert_raises(Adapters::Moxfield::InvalidUrl) { adapter.parse("") }
      end

      test "parse rejects non-Moxfield host" do
        adapter = Adapters::Moxfield.new(client: FakeClient.new)
        assert_raises(Adapters::Moxfield::InvalidUrl) do
          adapter.parse("https://archidekt.com/decks/12345")
        end
      end

      test "parse rejects URLs without a deck slug" do
        adapter = Adapters::Moxfield.new(client: FakeClient.new)
        assert_raises(Adapters::Moxfield::InvalidUrl) do
          adapter.parse("https://www.moxfield.com/")
        end
      end

      test "parse rejects malformed URLs" do
        adapter = Adapters::Moxfield.new(client: FakeClient.new)
        assert_raises(Adapters::Moxfield::InvalidUrl) do
          adapter.parse("not a url at all")
        end
      end

      test "parse translates 404 from the client into FetchFailed" do
        client = FakeClient.new(error: MoxfieldClient::NotFoundError.new("missing"))
        adapter = Adapters::Moxfield.new(client: client)
        error = assert_raises(Adapters::Moxfield::FetchFailed) do
          adapter.parse("https://www.moxfield.com/decks/abc123")
        end
        assert_match(/not found/i, error.message)
      end

      test "parse translates rate limit into FetchFailed" do
        client = FakeClient.new(error: MoxfieldClient::RateLimitedError.new("429"))
        adapter = Adapters::Moxfield.new(client: client)
        assert_raises(Adapters::Moxfield::FetchFailed) do
          adapter.parse("https://www.moxfield.com/decks/abc123")
        end
      end

      test "parse translates transport error into FetchFailed" do
        client = FakeClient.new(error: MoxfieldClient::TransportError.new("could not reach Moxfield"))
        adapter = Adapters::Moxfield.new(client: client)
        error = assert_raises(Adapters::Moxfield::FetchFailed) do
          adapter.parse("https://www.moxfield.com/decks/abc123")
        end
        assert_match(/Moxfield/i, error.message)
      end

      test "parse skips zero-quantity entries and missing names" do
        json = {
          "name" => "Tiny",
          "boards" => {
            "commanders" => {
              "cards" => {
                "atraxa" => { "quantity" => 1, "card" => { "name" => "Atraxa, Praetors' Voice" } }
              }
            },
            "mainboard" => {
              "cards" => {
                "zero" => { "quantity" => 0, "card" => { "name" => "Sol Ring" } },
                "blank" => { "quantity" => 1, "card" => { "name" => "" } }
              }
            }
          }
        }
        adapter = Adapters::Moxfield.new(client: FakeClient.new(response: json))
        parsed = adapter.parse("https://www.moxfield.com/decks/abc123")

        assert_equal 1, parsed.commanders.size
        assert_empty Array(parsed.boards["main"])
        assert parsed.unparsed_lines.any? { |l| l.include?("missing name") }
      end

      test "parse falls back to top-level board keys when boards hash is absent" do
        json = {
          "name" => "Flat Atraxa",
          "commanders" => {
            "cards" => {
              "atraxa" => { "quantity" => 1, "card" => { "name" => "Atraxa, Praetors' Voice" } }
            }
          },
          "mainboard" => {
            "cards" => {
              "sol" => { "quantity" => 1, "card" => { "name" => "Sol Ring" } }
            }
          }
        }
        adapter = Adapters::Moxfield.new(client: FakeClient.new(response: json))
        parsed = adapter.parse("https://www.moxfield.com/decks/abc123")

        assert_equal 1, parsed.commanders.size
        assert_equal [ "Sol Ring" ], parsed.boards["main"].map { |c| c[:name] }
      end
    end
  end
end
