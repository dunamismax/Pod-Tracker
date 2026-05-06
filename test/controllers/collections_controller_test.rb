require "test_helper"

class CollectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @sol_ring = create_oracle_card("Sol Ring")
    @arcane_signet = create_oracle_card("Arcane Signet")
  end

  test "shows the collection page" do
    sign_in_as(@user)
    @user.collection_cards.create!(name: "Sol Ring", oracle_card: @sol_ring, quantity: 2)

    get collection_path

    assert_response :success
    assert_select "h1", "Your collection"
    assert_select "p", /2 cards/
    assert_select "p", "Sol Ring"
  end

  test "imports pasted collection text and records audit event" do
    sign_in_as(@user)

    assert_difference -> { @user.collection_imports.count } => 1,
                      -> { @user.collection_cards.count } => 2,
                      -> { AuditEvent.where(event_name: "collection.imported").count } => 1 do
      post collection_imports_path, params: {
        collection_import_form: {
          collection_list: "2 Sol Ring\n1 Arcane Signet"
        }
      }
    end

    collection_import = @user.collection_imports.order(:id).last
    assert_redirected_to collection_import_path(collection_import)
    assert_equal 3, collection_import.imported_count
  end

  test "adds updates and removes a manual card" do
    sign_in_as(@user)

    assert_difference -> { @user.collection_cards.count } => 1 do
      post collection_cards_path, params: {
        collection_card: { name: "Sol Ring", quantity: 2 }
      }
    end

    card = @user.collection_cards.sole
    assert_redirected_to collection_path
    assert_equal 2, card.quantity

    patch collection_card_path(card), params: { collection_card: { quantity: 4 } }
    assert_equal 4, card.reload.quantity

    assert_difference -> { @user.collection_cards.count } => -1 do
      delete collection_card_path(card)
    end
  end

  test "resolves an unresolved import entry into the collection" do
    sign_in_as(@user)
    collection_import = @user.collection_imports.create!(source_type: "pasted_text")
    entry = @user.unresolved_entries.create!(
      collection_import: collection_import,
      name: "Sol Rin",
      quantity: 2,
      raw_line: "2 Sol Rin",
      reason: "No matching Scryfall card was found."
    )

    assert_difference -> { @user.collection_cards.count } => 1 do
      patch unresolved_entry_path(entry), params: {
        unresolved_entry: { name: "Sol Ring" }
      }
    end

    assert_equal "resolved", entry.reload.status
    assert_equal 2, @user.collection_cards.find_by!(normalized_name: "sol ring").quantity
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
