module Decks
  class TextDecklistParser
    BOARD_HEADERS = {
      "commander" => "commander",
      "commanders" => "commander",
      "mainboard" => "main",
      "main" => "main",
      "deck" => "main",
      "library" => "main",
      "sideboard" => "sideboard",
      "side" => "sideboard",
      "maybeboard" => "maybeboard",
      "maybe" => "maybeboard",
      "companion" => "companion"
    }.freeze

    LINE_PATTERN = /\A(?<quantity>\d+)\s*[xX]?\s+(?<name>.+?)(?:\s+\((?<set>[^)]+)\)\s*(?<collector>\S+)?)?\s*\z/

    Result = Struct.new(:commanders, :boards, :unparsed_lines, keyword_init: true) do
      def card_entries(board)
        boards.fetch(board, [])
      end

      def main_card_count
        boards.fetch("main", []).sum { |entry| entry.fetch(:quantity) }
      end

      def total_card_count
        commander_count + boards.values.flatten.sum { |entry| entry.fetch(:quantity) }
      end

      def commander_count
        commanders.sum { |entry| entry.fetch(:quantity) }
      end
    end

    def parse(text)
      commanders = []
      boards = Hash.new { |h, k| h[k] = [] }
      unparsed = []

      current_board = "main"
      position = Hash.new(0)

      text.to_s.each_line do |raw_line|
        line = raw_line.strip
        next if line.empty?
        next if line.start_with?("//")

        if (board = detect_board_header(line))
          current_board = board
          next
        end

        match = LINE_PATTERN.match(line)
        unless match
          unparsed << line
          next
        end

        entry = {
          quantity: match[:quantity].to_i,
          name: clean_name(match[:name]),
          set: match[:set]&.strip&.downcase,
          collector_number: match[:collector]&.strip,
          board: current_board
        }
        next if entry[:quantity] <= 0 || entry[:name].empty?

        if current_board == "commander"
          position[:commander] += 1
          entry[:position] = position[:commander]
          commanders << entry
        else
          position[current_board] += 1
          entry[:position] = position[current_board]
          boards[current_board] << entry
        end
      end

      Result.new(commanders: commanders, boards: boards, unparsed_lines: unparsed)
    end

    private

    def detect_board_header(line)
      stripped = line.sub(/\A#+\s*/, "").sub(/[:\-]\s*$/, "").downcase
      BOARD_HEADERS[stripped]
    end

    def clean_name(value)
      value.to_s.strip.sub(/\s+\*[A-Z]+\*\s*\z/, "").strip
    end
  end
end
