require "set"

module Scryfall
  class BulkImporter
    DEFAULT_BULK_TYPE = "default_cards"

    def initialize(client: Client.new)
      @client = client
    end

    def import!(bulk_type: DEFAULT_BULK_TYPE, source_io: nil, bulk_object: nil)
      bulk_object ||= @client.bulk_data_object(bulk_type)
      refresh = build_refresh(bulk_type, bulk_object)
      refresh.mark_running!

      counts = import_objects(source_io || @client.each_bulk_object(bulk_object.fetch("download_uri")))
      refresh.mark_succeeded!(counts)
      refresh
    rescue StandardError => error
      refresh&.mark_failed!(error)
      raise
    end

    private

    def build_refresh(bulk_type, bulk_object)
      CardCorpusRefresh.create!(
        source: "scryfall",
        bulk_type: bulk_type,
        status: "pending",
        source_uri: bulk_object.fetch("download_uri"),
        content_type: bulk_object["content_type"],
        content_length: bulk_object["size"],
        scryfall_updated_at: parse_time(bulk_object["updated_at"]),
        raw_payload: bulk_object
      )
    end

    def import_objects(objects)
      seen = {
        card_sets: Set.new,
        oracle_cards: Set.new,
        card_printings: Set.new
      }
      object_count = 0

      ActiveRecord::Base.transaction do
        each_object(objects) do |card|
          next unless card["object"] == "card"

          import_card(card, seen)
          object_count += 1
        end
      end

      {
        objects: object_count,
        card_sets: seen.fetch(:card_sets).size,
        oracle_cards: seen.fetch(:oracle_cards).size,
        card_printings: seen.fetch(:card_printings).size
      }
    end

    def each_object(objects)
      if objects.respond_to?(:read)
        JsonArrayStream.each(objects) { |object| yield object }
      else
        objects.each { |object| yield object }
      end
    end

    def import_card(card, seen)
      set = upsert_card_set(card)
      oracle = upsert_oracle_card(card)
      upsert_card_printing(card, set, oracle)

      seen.fetch(:card_sets) << set.code
      seen.fetch(:oracle_cards) << oracle.scryfall_oracle_id
      seen.fetch(:card_printings) << card.fetch("id")
    end

    def upsert_card_set(card)
      normalizer = CardNormalizer.new(card)
      card_set = CardSet.find_or_initialize_by(code: card.fetch("set"))
      card_set.assign_attributes(normalizer.card_set_attributes)
      card_set.save!
      card_set
    end

    def upsert_oracle_card(card)
      normalizer = CardNormalizer.new(card)
      oracle_card = OracleCard.find_or_initialize_by(scryfall_oracle_id: card.fetch("oracle_id"))
      oracle_card.assign_attributes(normalizer.oracle_attributes)
      oracle_card.save!
      oracle_card
    end

    def upsert_card_printing(card, card_set, oracle_card)
      normalizer = CardNormalizer.new(card)
      printing = CardPrinting.find_or_initialize_by(scryfall_id: card.fetch("id"))
      printing.assign_attributes(normalizer.printing_attributes(card_set: card_set, oracle_card: oracle_card))
      printing.save!
      printing
    end

    def parse_date(value)
      Date.iso8601(value) if value.present?
    end

    def parse_time(value)
      Time.zone.parse(value) if value.present?
    end
  end
end
