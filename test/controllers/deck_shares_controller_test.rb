require "test_helper"

class DeckSharesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @deck = create_deck_for(@user)
  end

  test "create issues a share token and records audit" do
    sign_in_as(@user)

    assert_difference -> { AuditEvent.where(event_name: "deck.share_enabled").count } => 1 do
      post deck_share_path(@deck)
    end

    assert_redirected_to deck_path(@deck)
    @deck.reload
    assert @deck.shared?
    assert @deck.share_token.present?
    assert @deck.shared_at.present?
    assert_nil @deck.share_revoked_at
  end

  test "create is idempotent — same token returned" do
    sign_in_as(@user)

    post deck_share_path(@deck)
    @deck.reload
    original_token = @deck.share_token

    post deck_share_path(@deck)
    @deck.reload
    assert_equal original_token, @deck.share_token
  end

  test "destroy revokes the share link" do
    sign_in_as(@user)
    @deck.issue_share_token!

    assert_difference -> { AuditEvent.where(event_name: "deck.share_revoked").count } => 1 do
      delete deck_share_path(@deck)
    end

    assert_redirected_to deck_path(@deck)
    @deck.reload
    refute @deck.shared?
    assert @deck.share_revoked_at.present?
  end

  test "rejects sharing another user's deck" do
    sign_in_as(@user)
    other_deck = users(:two).decks.create!(
      name: "Other deck",
      format: "commander",
      status: "imported",
      visibility: "private",
      source_type: "pasted_text"
    )

    post deck_share_path(other_deck)
    assert_response :not_found
    other_deck.reload
    refute other_deck.shared?
  end

  test "requires authentication" do
    post deck_share_path(@deck)
    assert_redirected_to new_session_path
  end

  private

    def create_deck_for(user)
      user.decks.create!(
        name: "Shareable deck",
        format: "commander",
        status: "imported",
        visibility: "private",
        source_type: "pasted_text",
        commander_names: [ "Atraxa, Praetors' Voice" ],
        last_imported_at: Time.current
      )
    end
end
