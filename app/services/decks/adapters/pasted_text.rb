module Decks
  module Adapters
    class PastedText < Base
      SOURCE_TYPE = "pasted_text".freeze

      def source_type
        SOURCE_TYPE
      end

      def parse(payload)
        text = payload.to_s
        result = TextDecklistParser.new.parse(text)
        ParsedDeck.new(
          name: nil,
          commanders: result.commanders,
          boards: result.boards.transform_values(&:itself),
          unparsed_lines: result.unparsed_lines,
          source_type: SOURCE_TYPE,
          source_url: nil,
          source_metadata: {
            "byte_size" => text.bytesize,
            "line_count" => text.each_line.count
          }
        )
      end
    end
  end
end
