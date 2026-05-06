module Collections
  class Importer
    Result = Struct.new(:collection_import, :error_messages, keyword_init: true) do
      def success?
        error_messages.empty? && collection_import&.persisted?
      end
    end

    def self.import_text(user:, payload:, filename: nil)
      new.import(user:, payload:, filename:, source_type: filename.to_s.downcase.end_with?(".csv") ? "csv" : "pasted_text")
    end

    def self.import_file(user:, file:)
      payload = file.respond_to?(:read) ? file.read : file.to_s
      filename = file.respond_to?(:original_filename) ? file.original_filename : nil
      source_type = filename.to_s.downcase.end_with?(".csv") ? "csv" : "uploaded_text"
      new.import(user:, payload:, filename:, source_type:)
    end

    def import(user:, payload:, filename: nil, source_type: "pasted_text")
      parsed = ImportParser.new.parse(payload, filename:)
      collection_import = nil

      CollectionImport.transaction do
        collection_import = user.collection_imports.create!(
          source_type: parsed.source_format == "csv" ? "csv" : source_type,
          original_filename: filename,
          status: "pending",
          metadata: {
            "line_count" => payload.to_s.each_line.count,
            "byte_size" => payload.to_s.bytesize,
            "unparsed_line_count" => parsed.unparsed_lines.size
          }
        )

        imported_count, unresolved_count = import_entries(user, collection_import, parsed.entries)
        unresolved_count += create_unparsed_entries(user, collection_import, parsed.unparsed_lines)

        collection_import.update!(
          imported_count: imported_count,
          unresolved_count: unresolved_count,
          status: unresolved_count.positive? ? "completed_with_unresolved" : "completed"
        )
      end

      Result.new(collection_import:, error_messages: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(collection_import: collection_import, error_messages: Array(e.record&.errors&.full_messages || [ e.message ]))
    end

    private

      def import_entries(user, collection_import, entries)
        normalized_names = entries.map { |entry| CollectionCard.normalize_card_name(entry.name) }
        lookup = CommanderFormat::OracleCardLookup.new
        lookup.preload(normalized_names)

        imported_count = 0
        unresolved_count = 0

        entries.each do |entry|
          normalized_name = CollectionCard.normalize_card_name(entry.name)
          oracle_card = lookup.lookup(normalized_name)

          if oracle_card
            upsert_collection_card(user, entry, normalized_name, oracle_card)
            imported_count += entry.quantity
          else
            create_unresolved_entry(
              user,
              collection_import,
              entry.raw_line,
              entry.name,
              entry.quantity,
              "No matching Scryfall card was found.",
              entry.metadata
            )
            unresolved_count += 1
          end
        end

        [ imported_count, unresolved_count ]
      end

      def upsert_collection_card(user, entry, normalized_name, oracle_card)
        card = user.collection_cards.find_or_initialize_by(normalized_name:)
        card.name = oracle_card.name.presence || entry.name
        card.oracle_card = oracle_card
        card.quantity = (card.persisted? ? card.quantity.to_i : 0) + entry.quantity.to_i
        card.source_type = "import"
        card.metadata = card.metadata.merge("last_imported_at" => Time.current.iso8601)
        card.save!
      end

      def create_unparsed_entries(user, collection_import, lines)
        lines.each do |line|
          create_unresolved_entry(user, collection_import, line, nil, 1, "Line could not be parsed.", {})
        end

        lines.size
      end

      def create_unresolved_entry(user, collection_import, raw_line, name, quantity, reason, metadata)
        user.unresolved_entries.create!(
          collection_import: collection_import,
          raw_line: raw_line,
          name: name,
          quantity: quantity,
          reason: reason,
          metadata: metadata
        )
      end
  end
end
