require "csv"

module Collections
  class ImportParser
    LINE_PATTERN = /\A(?:(?<quantity>\d+)\s*[xX]?\s+)?(?<name>.+?)\s*\z/
    QUANTITY_SUFFIX_PATTERN = /\A(?<name>.+?)\s+[xX](?<quantity>\d+)\z/

    Entry = Struct.new(:name, :quantity, :raw_line, :metadata, keyword_init: true)
    Result = Struct.new(:entries, :unparsed_lines, :source_format, keyword_init: true)

    def parse(text, filename: nil)
      source_format = csv_source?(text, filename) ? "csv" : "text"
      source_format == "csv" ? parse_csv(text, source_format:) : parse_text(text, source_format:)
    end

    private

      def csv_source?(text, filename)
        return true if File.extname(filename.to_s).downcase == ".csv"

        first_line = text.to_s.each_line.map(&:strip).find(&:present?)
        first_line.to_s.include?(",") && first_line.to_s.downcase.match?(/\b(name|card|quantity|count|qty)\b/)
      end

      def parse_csv(text, source_format:)
        entries = []
        unparsed = []
        table = CSV.parse(text.to_s, headers: true, skip_blanks: true)
        headers = Array(table.headers).map { |header| header.to_s.strip.downcase }

        table.each.with_index(2) do |csv_row, row_number|
          values = csv_row.fields.map { |value| value.to_s.strip }
          row = headers.zip(values).to_h
          name = csv_value(row, "name", "card", "card name")
          quantity = csv_value(row, "quantity", "qty", "count", "owned").to_i
          quantity = 1 if quantity <= 0
          raw_line = CSV.generate_line(values).to_s.strip

          if name.blank?
            unparsed << raw_line.presence || "CSV row #{row_number}"
            next
          end

          entries << Entry.new(
            name: clean_name(name),
            quantity: quantity,
            raw_line: raw_line,
            metadata: { "row" => row_number }
          )
        end

        Result.new(entries:, unparsed_lines: unparsed, source_format:)
      rescue CSV::MalformedCSVError
        Result.new(entries: [], unparsed_lines: text.to_s.each_line.map(&:strip).reject(&:blank?), source_format:)
      end

      def parse_text(text, source_format:)
        entries = []
        unparsed = []

        text.to_s.each_line do |raw_line|
          line = raw_line.strip
          next if line.empty?
          next if line.start_with?("//", "#")

          entry = parse_text_line(line)
          if entry
            entries << entry
          else
            unparsed << line
          end
        end

        Result.new(entries:, unparsed_lines: unparsed, source_format:)
      end

      def parse_text_line(line)
        match = LINE_PATTERN.match(line)
        return nil unless match

        name = clean_name(match[:name])
        quantity = match[:quantity].to_i
        quantity = 1 if quantity <= 0

        if (suffix = QUANTITY_SUFFIX_PATTERN.match(name))
          name = clean_name(suffix[:name])
          quantity = suffix[:quantity].to_i
        end

        return nil if name.blank?

        Entry.new(name:, quantity:, raw_line: line, metadata: {})
      end

      def csv_value(row, *keys)
        keys.each do |key|
          value = row[key]
          return value if value.present?
        end
        nil
      end

      def clean_name(value)
        value.to_s.strip.sub(/\s+\*[A-Z]+\*\s*\z/, "").strip
      end
  end
end
