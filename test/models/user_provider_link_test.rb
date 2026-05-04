require "test_helper"

class UserProviderLinkTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "stores a valid moxfield link" do
    link = @user.provider_links.create!(
      provider: "moxfield",
      handle: "TheUser",
      profile_url: "https://moxfield.com/users/TheUser"
    )

    assert link.persisted?
    assert_equal "theuser", link.normalized_handle
    assert_equal "Moxfield", link.provider_label
  end

  test "stores a valid archidekt link" do
    link = @user.provider_links.create!(
      provider: "archidekt",
      handle: "thedude",
      profile_url: "https://archidekt.com/u/thedude"
    )

    assert link.persisted?
    assert_equal "Archidekt", link.provider_label
  end

  test "rejects unsupported provider" do
    link = @user.provider_links.build(
      provider: "tappedout",
      handle: "x",
      profile_url: "https://tappedout.net/users/x"
    )
    refute link.valid?
    assert_includes link.errors[:provider], "is not included in the list"
  end

  test "rejects profile url that is not http(s)" do
    link = @user.provider_links.build(
      provider: "moxfield",
      handle: "TheUser",
      profile_url: "ftp://moxfield.com/users/TheUser"
    )
    refute link.valid?
    assert_includes link.errors[:profile_url], "must be an http(s) URL"
  end

  test "rejects profile url whose host does not match the provider" do
    link = @user.provider_links.build(
      provider: "moxfield",
      handle: "TheUser",
      profile_url: "https://archidekt.com/u/TheUser"
    )
    refute link.valid?
    assert_includes link.errors[:profile_url].first, "must point at moxfield.com"
  end

  test "rejects malformed url" do
    link = @user.provider_links.build(
      provider: "moxfield",
      handle: "TheUser",
      profile_url: "http:// bad url"
    )
    refute link.valid?
    assert_includes link.errors[:profile_url], "must be a valid URL"
  end

  test "enforces unique handle per user and provider, case-insensitively" do
    @user.provider_links.create!(
      provider: "moxfield",
      handle: "TheUser",
      profile_url: "https://moxfield.com/users/TheUser"
    )

    duplicate = @user.provider_links.build(
      provider: "moxfield",
      handle: "theuser",
      profile_url: "https://moxfield.com/users/theuser"
    )
    refute duplicate.valid?
    assert_includes duplicate.errors[:normalized_handle], "has already been taken"
  end

  test "allows the same handle on a different provider" do
    @user.provider_links.create!(
      provider: "moxfield",
      handle: "shared",
      profile_url: "https://moxfield.com/users/shared"
    )
    other = @user.provider_links.create!(
      provider: "archidekt",
      handle: "shared",
      profile_url: "https://archidekt.com/u/shared"
    )
    assert other.persisted?
  end

  test "allows the same handle on a different user" do
    @user.provider_links.create!(
      provider: "moxfield",
      handle: "shared",
      profile_url: "https://moxfield.com/users/shared"
    )
    other = users(:two).provider_links.create!(
      provider: "moxfield",
      handle: "shared",
      profile_url: "https://moxfield.com/users/shared"
    )
    assert other.persisted?
  end

  test "schema does not expose any password column" do
    columns = UserProviderLink.column_names.map(&:to_s)
    columns.each do |column|
      refute_match(/password|secret|token|credential/i, column,
        "UserProviderLink must never include credential-like columns; found #{column}")
    end
  end

  test "export payload omits user_id and never includes credentials" do
    link = @user.provider_links.create!(
      provider: "moxfield",
      handle: "TheUser",
      profile_url: "https://moxfield.com/users/TheUser",
      label: "Main",
      notes: "Brewing"
    )

    payload = link.export_payload
    assert_equal "moxfield", payload[:provider]
    assert_equal "TheUser", payload[:handle]
    assert_equal "Main", payload[:label]
    refute payload.key?(:user_id)
    refute payload.key?(:password)
  end
end
