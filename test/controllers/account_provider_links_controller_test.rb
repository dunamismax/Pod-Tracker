require "test_helper"

class AccountProviderLinksControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "requires authentication for new" do
    get new_account_provider_link_path
    assert_redirected_to new_session_path
  end

  test "requires authentication for create" do
    post account_provider_links_path, params: { user_provider_link: { provider: "moxfield", handle: "x", profile_url: "https://moxfield.com/users/x" } }
    assert_redirected_to new_session_path
  end

  test "renders the new form for an authenticated user" do
    sign_in_as(@user)
    get new_account_provider_link_path
    assert_response :success
    assert_select "form"
    # Form must never expose a password input for the third-party provider.
    assert_select "input[type=password]", count: 0
  end

  test "creates a provider link and records an audit event" do
    sign_in_as(@user)

    assert_difference -> { @user.provider_links.count } => 1,
                       -> { AuditEvent.where(event_name: "provider_link.created").count } => 1 do
      post account_provider_links_path, params: {
        user_provider_link: {
          provider: "moxfield",
          handle: "PlayerOne",
          profile_url: "https://moxfield.com/users/PlayerOne",
          label: "Main account"
        }
      }
    end

    assert_redirected_to account_path
    link = @user.provider_links.order(:id).last
    assert_equal "moxfield", link.provider
    assert_equal "PlayerOne", link.handle
    assert_equal "playerone", link.normalized_handle

    event = AuditEvent.where(event_name: "provider_link.created").last
    assert_equal @user.id, event.user_id
    assert_equal "moxfield", event.metadata["provider"]
    assert_equal "PlayerOne", event.metadata["handle"]
  end

  test "rejects creation when the provider is unsupported" do
    sign_in_as(@user)

    assert_no_difference -> { @user.provider_links.count } do
      post account_provider_links_path, params: {
        user_provider_link: {
          provider: "tappedout",
          handle: "x",
          profile_url: "https://tappedout.net/users/x"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "rejects password-like params silently" do
    sign_in_as(@user)
    post account_provider_links_path, params: {
      user_provider_link: {
        provider: "moxfield",
        handle: "PlayerOne",
        profile_url: "https://moxfield.com/users/PlayerOne",
        password: "should-be-ignored"
      }
    }

    assert_redirected_to account_path
    link = @user.provider_links.order(:id).last
    assert_not_respond_to link, :password
  end

  test "destroys a provider link and records an audit event" do
    link = @user.provider_links.create!(
      provider: "moxfield",
      handle: "PlayerOne",
      profile_url: "https://moxfield.com/users/PlayerOne"
    )
    sign_in_as(@user)

    assert_difference -> { @user.provider_links.count } => -1,
                       -> { AuditEvent.where(event_name: "provider_link.removed").count } => 1 do
      delete account_provider_link_path(link)
    end

    assert_redirected_to account_path
    event = AuditEvent.where(event_name: "provider_link.removed").last
    assert_equal "moxfield", event.metadata["provider"]
    assert_equal "PlayerOne", event.metadata["handle"]
  end

  test "cannot destroy another user's link" do
    other_link = users(:two).provider_links.create!(
      provider: "moxfield",
      handle: "TwoHandle",
      profile_url: "https://moxfield.com/users/TwoHandle"
    )
    sign_in_as(@user)

    assert_no_difference -> { UserProviderLink.count } do
      delete account_provider_link_path(other_link)
    end
    assert_response :not_found
  end

  test "account show page lists existing provider links and add button" do
    @user.provider_links.create!(
      provider: "moxfield",
      handle: "PlayerOne",
      profile_url: "https://moxfield.com/users/PlayerOne"
    )
    sign_in_as(@user)

    get account_path
    assert_response :success
    assert_select "h2", text: /Provider account links/
    assert_select "a[href=?]", new_account_provider_link_path
    assert_select "li", text: /Moxfield · PlayerOne/
  end
end
