require "test_helper"

class AccountDeletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "rejects deletion when password is wrong" do
    sign_in_as(@user)
    assert_no_difference("User.count") do
      delete account_deletion_path, params: { current_password: "wrong-password" }
    end
    assert_response :unprocessable_entity
  end

  test "deletes user, terminates session, and records audit event when password matches" do
    sign_in_as(@user)
    deck = @user.decks.create!(name: "Doomed Deck")

    assert_difference("User.count", -1) do
      assert_difference("Deck.count", -1) do
        delete account_deletion_path, params: { current_password: "password" }
      end
    end

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id].presence
    assert_not Deck.exists?(deck.id)

    event = AuditEvent.where(event_name: "account.deleted").last
    assert_not_nil event
    assert_nil event.user_id, "user_id should be nullified after deletion"
    assert_equal @user.email_address, event.metadata["email_address"]
  end
end
