module Decks
  module Adapters
    class TextFile < Base
      SOURCE_TYPE = "text_file".freeze
      MAX_BYTES = 64.kilobytes
      ALLOWED_CONTENT_TYPES = %w[
        text/plain
        text/markdown
        text/x-markdown
        text/csv
        application/octet-stream
      ].freeze
      ALLOWED_EXTENSIONS = %w[.txt .text .dec .deck .cod .md .markdown .csv].freeze

      class InvalidFile < StandardError; end

      def source_type
        SOURCE_TYPE
      end

      def parse(payload)
        text, metadata = read_payload(payload)
        result = TextDecklistParser.new.parse(text)

        ParsedDeck.new(
          name: nil,
          commanders: result.commanders,
          boards: result.boards.transform_values(&:itself),
          unparsed_lines: result.unparsed_lines,
          source_type: SOURCE_TYPE,
          source_url: nil,
          source_metadata: metadata.merge(
            "byte_size" => text.bytesize,
            "line_count" => text.each_line.count
          )
        )
      end

      private

      def read_payload(payload)
        raise InvalidFile, "No file was uploaded." if payload.nil?
        raise InvalidFile, "Uploaded file is missing read access." unless payload.respond_to?(:read)

        original_filename = payload.respond_to?(:original_filename) ? payload.original_filename.to_s : ""
        content_type = payload.respond_to?(:content_type) ? payload.content_type.to_s : ""
        declared_size = payload.respond_to?(:size) ? payload.size.to_i : nil

        if declared_size && declared_size > MAX_BYTES
          raise InvalidFile, "Uploaded file is too large (limit #{MAX_BYTES / 1024} KB)."
        end

        check_extension!(original_filename) if original_filename.present?
        check_content_type!(content_type) if content_type.present?

        bytes = payload.read(MAX_BYTES + 1)
        bytes = bytes.to_s
        if bytes.bytesize > MAX_BYTES
          raise InvalidFile, "Uploaded file is too large (limit #{MAX_BYTES / 1024} KB)."
        end

        text = decode_text(bytes)

        metadata = {
          "filename" => original_filename.presence,
          "content_type" => content_type.presence,
          "uploaded_byte_size" => bytes.bytesize
        }.compact

        [ text, metadata ]
      ensure
        payload.rewind if payload.respond_to?(:rewind)
      end

      def check_extension!(filename)
        ext = File.extname(filename).downcase
        return if ext.empty?
        return if ALLOWED_EXTENSIONS.include?(ext)

        raise InvalidFile, "Unsupported file extension '#{ext}'. Upload a plain-text decklist (.txt)."
      end

      def check_content_type!(content_type)
        normalized = content_type.split(";").first.to_s.strip.downcase
        return if normalized.empty?
        return if ALLOWED_CONTENT_TYPES.include?(normalized)
        return if normalized.start_with?("text/")

        raise InvalidFile, "Unsupported file type '#{normalized}'. Upload a plain-text decklist."
      end

      def decode_text(bytes)
        utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
        unless utf8.valid_encoding?
          raise InvalidFile, "File is not valid UTF-8 text. Save it as plain text and try again."
        end

        utf8.delete_prefix("﻿")
      end
    end
  end
end
