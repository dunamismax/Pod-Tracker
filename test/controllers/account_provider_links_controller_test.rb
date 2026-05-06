require "test_helper"

class AccountProviderLinksControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

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
end
