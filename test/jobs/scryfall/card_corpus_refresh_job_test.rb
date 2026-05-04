require "test_helper"

module Scryfall
  class CardCorpusRefreshJobTest < ActiveJob::TestCase
    test "enqueues onto the dedicated card corpus queue" do
      assert_enqueued_with(job: CardCorpusRefreshJob, queue: "card_corpus") do
        CardCorpusRefreshJob.perform_later
      end
    end

    test "perform delegates the bulk type into the bulk importer" do
      stub_importer = StubImporter.new
      CardCorpusRefreshJob.perform_now(bulk_type: "default_cards", importer: stub_importer)

      assert_equal([ "default_cards" ], stub_importer.calls)
    end

    test "perform completes a Scryfall ingestion against a stubbed bulk source and stores refresh metadata" do
      bulk_object = {
        "type" => "default_cards",
        "download_uri" => "https://data.scryfall.io/default-cards/job-test.json",
        "content_type" => "application/json",
        "size" => 256,
        "updated_at" => "2026-05-04T10:11:12.000+00:00"
      }
      card = scryfall_card_payload
      client = StubClient.new(bulk_object: bulk_object, body: [ card ].to_json)
      importer = BulkImporter.new(client: client)

      assert_difference -> { CardCorpusRefresh.count }, +1 do
        CardCorpusRefreshJob.perform_now(importer: importer)
      end

      refresh = CardCorpusRefresh.order(:created_at).last
      assert_equal("succeeded", refresh.status)
      assert_equal("default_cards", refresh.bulk_type)
      assert_equal(1, refresh.object_count)
      assert(OracleCard.find_by(name: "Test Card"))
    end

    private

    def scryfall_card_payload
      {
        "object" => "card",
        "id" => SecureRandom.uuid,
        "oracle_id" => SecureRandom.uuid,
        "set_id" => SecureRandom.uuid,
        "set" => "tst",
        "set_name" => "Job Test Set",
        "set_type" => "expansion",
        "lang" => "en",
        "name" => "Test Card",
        "layout" => "normal",
        "mana_cost" => "{1}",
        "cmc" => 1.0,
        "type_line" => "Artifact",
        "oracle_text" => "Do nothing.",
        "colors" => [],
        "color_identity" => [],
        "collector_number" => "1",
        "released_at" => "2026-05-04",
        "rarity" => "common",
        "image_status" => "highres_scan",
        "image_uris" => {},
        "legalities" => { "commander" => "legal" },
        "prices" => {},
        "purchase_uris" => {},
        "reserved" => false,
        "digital" => false,
        "keywords" => []
      }
    end

    class StubImporter
      attr_reader :calls

      def initialize
        @calls = []
      end

      def import!(bulk_type:)
        @calls << bulk_type
        :stubbed
      end
    end

    class StubClient
      def initialize(bulk_object:, body:)
        @bulk_object = bulk_object
        @body = body
      end

      def bulk_data_object(_type)
        @bulk_object
      end

      def each_bulk_object(_uri)
        return enum_for(:each_bulk_object, nil) unless block_given?

        StringIO.open(@body) do |io|
          JsonArrayStream.new(enumerator_for(io)).each { |object| yield object }
        end
      end

      private

      def enumerator_for(io)
        Enumerator.new do |yielder|
          while (chunk = io.read(64))
            yielder << chunk
          end
        end
      end
    end
  end
end
