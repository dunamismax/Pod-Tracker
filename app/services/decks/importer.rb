module Decks
  class Importer
    Result = Struct.new(:deck, :parsed, :error_messages, keyword_init: true) do
      def success?
        error_messages.empty? && deck&.persisted?
      end
    end

    def self.import_pasted_text(user:, payload:, name: nil, commander_hint: nil)
      new.import(
        user: user,
        adapter: Adapters::PastedText.new,
        payload: payload,
        name: name,
        commander_hint: commander_hint
      )
    end

    def import(user:, adapter:, payload:, name: nil, commander_hint: nil)
      parsed = adapter.parse(payload)
      parsed_with_hint = apply_commander_hint(parsed, commander_hint)
      errors = validate(parsed_with_hint)

      if errors.any?
        return Result.new(deck: nil, parsed: parsed_with_hint, error_messages: errors)
      end

      deck = build_deck(user: user, parsed: parsed_with_hint, name: name)
      Deck.transaction do
        deck.save!
      end
      Result.new(deck: deck, parsed: parsed_with_hint, error_messages: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(deck: nil, parsed: parsed, error_messages: Array(e.record&.errors&.full_messages || [ e.message ]))
    end

    private

    def apply_commander_hint(parsed, hint)
      cleaned = hint.to_s.strip
      return parsed if cleaned.empty?
      return parsed unless parsed.commanders.empty?

      hinted_commander = {
        quantity: 1,
        name: cleaned,
        set: nil,
        collector_number: nil,
        board: "commander",
        position: 1
      }
      Adapters::Base::ParsedDeck.new(
        name: parsed.name,
        commanders: [ hinted_commander ],
        boards: parsed.boards,
        unparsed_lines: parsed.unparsed_lines,
        source_type: parsed.source_type,
        source_url: parsed.source_url,
        source_metadata: parsed.source_metadata
      )
    end

    def validate(parsed)
      errors = []
      if parsed.commanders.empty?
        errors << "Decklist must include a commander. Add a 'Commander' header or pick one in the form."
      end
      if parsed.boards.values.flatten.empty?
        errors << "Decklist appears empty after parsing. Check the format and try again."
      end
      errors
    end

    def build_deck(user:, parsed:, name:)
      derived_name = derive_name(parsed, name)
      deck = Deck.new(
        user: user,
        name: derived_name,
        format: "commander",
        status: "imported",
        visibility: "private",
        source_type: parsed.source_type,
        color_identity: [],
        commander_names: parsed.commanders.map { |entry| entry[:name] },
        last_imported_at: Time.current,
        import_metadata: {
          "source_type" => parsed.source_type,
          "source_url" => parsed.source_url,
          "source_metadata" => parsed.source_metadata,
          "unparsed_lines" => parsed.unparsed_lines,
          "imported_at" => Time.current.iso8601
        }.compact
      )

      parsed.commanders.each_with_index do |attrs, index|
        deck.commanders.build(
          name: attrs[:name],
          position: attrs[:position] || index + 1,
          raw_line: raw_line_for(attrs)
        )
      end

      parsed.boards.each do |board, entries|
        entries.each do |attrs|
          deck.deck_cards.build(
            name: attrs[:name],
            quantity: attrs[:quantity],
            board: board,
            position: attrs[:position],
            raw_line: raw_line_for(attrs),
            metadata: card_metadata(attrs)
          )
        end
      end

      deck
    end

    def derive_name(parsed, supplied_name)
      cleaned = supplied_name.to_s.strip
      return cleaned if cleaned.present?

      commander_label = parsed.commanders.map { |c| c[:name] }.compact.first
      return commander_label if commander_label.present?

      "Imported deck #{Time.current.utc.strftime('%Y-%m-%d %H:%M')}"
    end

    def raw_line_for(attrs)
      base = "#{attrs[:quantity]} #{attrs[:name]}"
      base += " (#{attrs[:set]})" if attrs[:set].present?
      base += " #{attrs[:collector_number]}" if attrs[:collector_number].present?
      base
    end

    def card_metadata(attrs)
      metadata = {}
      metadata["set_code"] = attrs[:set] if attrs[:set].present?
      metadata["collector_number"] = attrs[:collector_number] if attrs[:collector_number].present?
      metadata
    end
  end
end
