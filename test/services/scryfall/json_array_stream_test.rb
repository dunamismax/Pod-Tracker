require "test_helper"

module Scryfall
  class JsonArrayStreamTest < ActiveSupport::TestCase
    test "yields objects from a chunked top-level JSON array" do
      chunks = [
        "[{\"id\":\"one\",\"nested\":{\"text\":\"brace } in string\"}},",
        "{\"id\":\"two\",\"faces\":[{\"name\":\"A\"},{\"name\":\"B\"}]}]"
      ]

      objects = JsonArrayStream.new(chunks).to_a

      assert_equal(%w[one two], objects.map { |object| object.fetch("id") })
      assert_equal("brace } in string", objects.first.dig("nested", "text"))
      assert_equal(2, objects.second.fetch("faces").size)
    end

    test "raises when the final object is incomplete" do
      error = assert_raises(JSON::ParserError) do
        JsonArrayStream.new([ "[{\"id\":\"one\"" ]).to_a
      end

      assert_match(/unterminated JSON object/, error.message)
    end
  end
end
