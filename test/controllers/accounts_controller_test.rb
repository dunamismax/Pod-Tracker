require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "redirects unauthenticated users" do
    get account_path
    assert_redirected_to new_session_path
  end

  test "shows account for signed-in user" do
    sign_in_as(@user)
    get account_path
    assert_response :success
    assert_select "h1", text: /Account/
  end

  test "edit renders form" do
    sign_in_as(@user)
    get edit_account_path
    assert_response :success
  end

  test "update saves valid changes" do
    sign_in_as(@user)
    patch account_path, params: { user: { display_name: "Renamed", timezone: "Etc/UTC", preferred_units: "metric" } }
    assert_redirected_to account_path
    @user.reload
    assert_equal "Renamed", @user.display_name
    assert_equal "metric", @user.preferred_units
  end

  test "update rejects invalid units" do
    sign_in_as(@user)
    patch account_path, params: { user: { preferred_units: "league" } }
    assert_response :unprocessable_entity
  end

  test "update ignores email and password changes" do
    sign_in_as(@user)
    original_email = @user.email_address
    original_digest = @user.password_digest
    patch account_path, params: { user: { email_address: "hijack@example.com", password: "newpass" } }
    @user.reload
    assert_equal original_email, @user.email_address
    assert_equal original_digest, @user.password_digest
  end
end
