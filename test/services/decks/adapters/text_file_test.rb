require "test_helper"

module Decks
  module Adapters
    class TextFileTest < ActiveSupport::TestCase
      DECKLIST = <<~TXT.freeze
        Commander
        1 Atraxa, Praetors' Voice

        Mainboard
        1 Sol Ring
        1 Arcane Signet
        1 Command Tower
      TXT

      test "source_type is text_file" do
        assert_equal "text_file", Adapters::TextFile.new.source_type
      end

      test "parse reads an uploaded file and returns a structured ParsedDeck" do
        upload = uploaded_file(DECKLIST, filename: "atraxa.txt", content_type: "text/plain")

        parsed = Adapters::TextFile.new.parse(upload)

        assert_equal "text_file", parsed.source_type
        assert_nil parsed.source_url
        assert_equal "atraxa.txt", parsed.source_metadata["filename"]
        assert_equal "text/plain", parsed.source_metadata["content_type"]
        assert_operator parsed.source_metadata["uploaded_byte_size"], :>, 0
        assert_operator parsed.source_metadata["byte_size"], :>, 0

        assert_equal 1, parsed.commanders.size
        assert_equal "Atraxa, Praetors' Voice", parsed.commanders.first[:name]
        assert_equal 3, parsed.boards["main"].size
        assert_empty parsed.unparsed_lines
      end

      test "parse strips a UTF-8 BOM" do
        bom = [ 0xEF, 0xBB, 0xBF ].pack("C*")
        upload = uploaded_file("#{bom}Commander\n1 Atraxa, Praetors' Voice\nMainboard\n1 Sol Ring\n", filename: "deck.txt")

        parsed = Adapters::TextFile.new.parse(upload)
        assert_equal 1, parsed.commanders.size
        assert_equal "Atraxa, Praetors' Voice", parsed.commanders.first[:name]
      end

      test "parse rejects nil payload" do
        assert_raises(Adapters::TextFile::InvalidFile) { Adapters::TextFile.new.parse(nil) }
      end

      test "parse rejects unsupported extensions" do
        upload = uploaded_file(DECKLIST, filename: "deck.exe", content_type: "application/octet-stream")
        assert_raises(Adapters::TextFile::InvalidFile) { Adapters::TextFile.new.parse(upload) }
      end

      test "parse rejects unsupported content types" do
        upload = uploaded_file(DECKLIST, filename: "deck.txt", content_type: "image/png")
        assert_raises(Adapters::TextFile::InvalidFile) { Adapters::TextFile.new.parse(upload) }
      end

      test "parse rejects files over the size limit" do
        oversize = "1 Sol Ring\n" * (Adapters::TextFile::MAX_BYTES / 10)
        upload = uploaded_file(oversize, filename: "huge.txt", content_type: "text/plain")
        assert_raises(Adapters::TextFile::InvalidFile) { Adapters::TextFile.new.parse(upload) }
      end

      test "parse rejects non-UTF-8 bytes" do
        invalid = "Commander\n1 Atraxa\xFF\xFE invalid".dup.force_encoding(Encoding::BINARY)
        upload = uploaded_file(invalid, filename: "deck.txt", content_type: "text/plain")
        assert_raises(Adapters::TextFile::InvalidFile) { Adapters::TextFile.new.parse(upload) }
      end

      private

      def uploaded_file(content, filename:, content_type: "text/plain")
        tempfile = Tempfile.new([ "deck", File.extname(filename) ])
        tempfile.binmode
        tempfile.write(content)
        tempfile.rewind
        ActionDispatch::Http::UploadedFile.new(
          tempfile: tempfile,
          filename: filename,
          type: content_type
        )
      end
    end
  end
end
