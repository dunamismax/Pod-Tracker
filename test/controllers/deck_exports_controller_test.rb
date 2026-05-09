require "test_helper"

class DeckExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @deck = create_deck_for(@user)
  end

  test "downloads decklist as text" do
    sign_in_as(@user)

    get deck_export_path(@deck, format: :text)
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match(/^attachment;/, response.headers["Content-Disposition"])
    assert_match(/pod-tracker-deck-existing-deck-/, response.headers["Content-Disposition"])
    assert_includes response.body, "1 Sol Ring"
  end

  test "downloads decklist as csv" do
    sign_in_as(@user)

    get deck_export_path(@deck, format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type
    rows = CSV.parse(response.body)
    assert_equal %w[board quantity name], rows.first
    assert_includes rows, [ "main", "1", "Sol Ring" ]
  end

  test "downloads decklist as json" do
    sign_in_as(@user)

    get deck_export_path(@deck, format: :json)
    assert_response :success
    parsed = JSON.parse(response.body)
    assert_equal "Existing deck", parsed["deck"]["name"]
  end

  test "rejects export of another user's deck" do
    sign_in_as(@user)
    other = users(:two).decks.create!(
      name: "Other deck",
      format: "commander",
      status: "imported",
      visibility: "private",
      source_type: "pasted_text"
    )

    get deck_export_path(other, format: :text)
    assert_response :not_found
  end

  test "requires authentication" do
    get deck_export_path(@deck, format: :text)
    assert_redirected_to new_session_path
  end

  private

    def create_deck_for(user)
      deck = user.decks.create!(
        name: "Existing deck",
        format: "commander",
        status: "imported",
        visibility: "private",
        source_type: "pasted_text",
        commander_names: [ "Atraxa, Praetors' Voice" ],
        last_imported_at: Time.current
      )
      deck.commanders.create!(name: "Atraxa, Praetors' Voice", position: 1)
      deck.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 1)
      deck
    end
end
