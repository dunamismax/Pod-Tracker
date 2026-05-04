require "test_helper"

class AccountExportsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "redirects unauthenticated users" do
    post account_export_path
    assert_redirected_to new_session_path
  end

  test "returns a downloadable JSON payload with the user's data" do
    sign_in_as(@user)
    deck = @user.decks.create!(name: "Goblin Stompy")
    deck.deck_cards.create!(name: "Lightning Bolt", quantity: 1)

    post account_export_path

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_match(/attachment; filename=/, response.headers["Content-Disposition"])

    body = JSON.parse(response.body)
    assert_equal Accounts::Exporter::SCHEMA_VERSION, body["schema_version"]
    assert_equal @user.email_address, body["account"]["email_address"]
    assert_equal 1, body["decks"].size
    assert_equal "Goblin Stompy", body["decks"].first["name"]
    assert_equal 1, body["decks"].first["cards"].size
  end

  test "records an account.exported audit event" do
    sign_in_as(@user)

    assert_difference -> { AuditEvent.where(event_name: "account.exported").count }, 1 do
      post account_export_path
    end

    event = AuditEvent.where(event_name: "account.exported", user: @user).last
    assert_equal Accounts::Exporter::SCHEMA_VERSION, event.metadata["schema_version"]
  end
end
