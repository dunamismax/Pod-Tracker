require "application_system_test_case"

class AccountAuthFlowsTest < ApplicationSystemTestCase
  test "user signs up, signs out, and signs back in" do
    visit new_registration_path

    fill_in "user_email_address", with: "new-player@example.com"
    fill_in "user_display_name", with: "New Player"
    fill_in "user_password", with: "correct horse battery staple"
    fill_in "user_password_confirmation", with: "correct horse battery staple"
    click_button "Create account"

    assert_text "Account created. Check your email to verify your address."
    assert_text "Ideal Magic"

    visit account_path
    assert_text "new-player@example.com"
    assert_text "New Player"

    click_button "Sign out"
    assert_text "Sign in"

    fill_in "email_address", with: "new-player@example.com"
    fill_in "password", with: "correct horse battery staple"
    click_button "Sign in"

    assert_text "Ideal Magic"
  end

  test "user resets password from reset email token" do
    user = users(:one)

    visit new_password_path
    fill_in "email_address", with: user.email_address
    click_button "Email reset instructions"

    assert_text "Password reset instructions sent"

    visit edit_password_path(user.reload.password_reset_token)
    fill_in "password", with: "fresh secure password"
    fill_in "password_confirmation", with: "fresh secure password"
    click_button "Save"

    assert_text "Password has been reset."

    fill_in "email_address", with: user.email_address
    fill_in "password", with: "fresh secure password"
    click_button "Sign in"

    assert_text "Ideal Magic"
  end

  test "user deletes account after password confirmation" do
    user = users(:two)

    sign_in_through_ui(user)
    visit new_account_deletion_path

    fill_in "current_password", with: "wrong-password"
    click_button "Delete my account"

    assert_text "Password did not match."
    assert User.exists?(user.id)

    fill_in "current_password", with: "password"
    click_button "Delete my account"

    assert_text "Account deleted."
    refute User.exists?(user.id)
    assert_equal "account.deleted", AuditEvent.last.event_name
  end

  test "account page shows Codex account status without exposing credential material" do
    user = users(:one)
    CodexAccount.create!(
      user: user,
      auth_mode: "chatgpt_browser",
      status: "connected",
      displayed_email: "chatgpt-user@example.com",
      plan_type: "plus",
      encrypted_credential_payload: "secret-browser-token",
      credential_metadata: { token_kind: "chatgpt_session", refresh_hint: "rotate-soon" },
      rate_limit_snapshot: { "remaining" => 20 }
    )

    sign_in_through_ui(user)
    visit account_path

    assert_text "Codex account"
    assert_text "Connected"
    assert_text "chatgpt-user@example.com"
    assert_text "plus"
    assert_no_text "secret-browser-token"
    assert_no_text "chatgpt_session"
    assert_no_text "rotate-soon"
  end

  private
    def sign_in_through_ui(user, password: "password")
      visit new_session_path
      fill_in "email_address", with: user.email_address
      fill_in "password", with: password
      click_button "Sign in"

      assert_text "Ideal Magic"
    end
end
