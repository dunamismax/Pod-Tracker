module Decks
  module Adapters
    class Base
      ParsedDeck = Struct.new(
        :name, :commanders, :boards, :unparsed_lines,
        :source_type, :source_url, :source_metadata,
        keyword_init: true
      ) do
        def commander_count
          commanders.sum { |c| c.fetch(:quantity, 1) }
        end

        def main_card_count
          boards.fetch("main", []).sum { |entry| entry.fetch(:quantity) }
        end

        def total_card_count
          commander_count + boards.values.flatten.sum { |entry| entry.fetch(:quantity) }
        end
      end

      def source_type
        raise NotImplementedError, "#{self.class}#source_type must be implemented"
      end

      def parse(_payload)
        raise NotImplementedError, "#{self.class}#parse must be implemented"
      end

      def fetch(_payload)
        raise NotImplementedError, "#{self.class}#fetch is not implemented for this adapter"
      end

      def refresh(_deck)
        raise NotImplementedError, "#{self.class}#refresh is not implemented for this adapter"
      end
    end
  end
end
