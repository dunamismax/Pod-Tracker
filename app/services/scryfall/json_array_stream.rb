require "json"

module Scryfall
  class JsonArrayStream
    include Enumerable

    def self.each(io, &block)
      new(io.each).each(&block)
    end

    def initialize(chunks)
      @chunks = chunks
    end

    def each
      return enum_for(:each) unless block_given?

      buffer = +""
      collecting = false
      depth = 0
      in_string = false
      escaped = false

      @chunks.each do |chunk|
        chunk.each_char do |char|
          unless collecting
            next unless char == "{"

            collecting = true
            depth = 1
            buffer << char
            next
          end

          buffer << char

          if in_string
            if escaped
              escaped = false
            elsif char == "\\"
              escaped = true
            elsif char == "\""
              in_string = false
            end
          elsif char == "\""
            in_string = true
          elsif char == "{"
            depth += 1
          elsif char == "}"
            depth -= 1

            if depth.zero?
              yield JSON.parse(buffer)
              buffer.clear
              collecting = false
            end
          end
        end
      end

      raise JSON::ParserError, "unterminated JSON object in Scryfall bulk payload" if collecting
    end
  end
end
