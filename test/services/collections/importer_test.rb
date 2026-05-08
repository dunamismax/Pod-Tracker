require "test_helper"

module Collections
  class ImporterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @sol_ring = create_oracle_card("Sol Ring")
      @arcane_signet = create_oracle_card("Arcane Signet")
    end

    test "imports text rows and keeps unresolved names for review" do
      result = Importer.import_text(
        user: @user,
        payload: <<~TXT
          2 Sol Ring
          Arcane Signet x3
          1 Made Up Card
        TXT
      )

      assert result.success?
      assert_equal 5, result.collection_import.imported_count
      assert_equal 1, result.collection_import.unresolved_count
      assert_equal "completed_with_unresolved", result.collection_import.status

      assert_equal 2, @user.collection_cards.find_by!(normalized_name: "sol ring").quantity
      assert_equal 3, @user.collection_cards.find_by!(normalized_name: "arcane signet").quantity

      unresolved = result.collection_import.unresolved_entries.sole
      assert_equal "Made Up Card", unresolved.name
      assert_equal 1, unresolved.quantity
      assert_equal "No matching Scryfall card was found.", unresolved.reason
    end

    test "imports simple CSV rows and accumulates existing quantities" do
      @user.collection_cards.create!(name: "Sol Ring", normalized_name: "sol ring", oracle_card: @sol_ring, quantity: 1)

      result = Importer.import_text(
        user: @user,
        filename: "collection.csv",
        payload: <<~CSV
          name,quantity
          Sol Ring,2
          Arcane Signet,4
        CSV
      )

      assert result.success?
      assert_equal "csv", result.collection_import.source_type
      assert_equal 3, @user.collection_cards.find_by!(normalized_name: "sol ring").quantity
      assert_equal 4, @user.collection_cards.find_by!(normalized_name: "arcane signet").quantity
    end

    test "imports quoted CSV card names containing commas" do
      yuriko = create_oracle_card("Yuriko, the Tiger's Shadow")

      result = Importer.import_text(
        user: @user,
        filename: "collection.csv",
        payload: <<~CSV
          name,quantity
          "Yuriko, the Tiger's Shadow",1
        CSV
      )

      assert result.success?
      assert_equal "csv", result.collection_import.source_type
      assert_equal 0, result.collection_import.unresolved_count
      collection_card = @user.collection_cards.find_by!(normalized_name: yuriko.normalized_name)
      assert_equal "Yuriko, the Tiger's Shadow", collection_card.name
      assert_equal 1, collection_card.quantity
    end

    private

      def create_oracle_card(name)
        OracleCard.create!(
          name: name,
          normalized_name: ApplicationRecord.normalize_card_name(name),
          scryfall_oracle_id: SecureRandom.uuid
        )
      end
  end
end
