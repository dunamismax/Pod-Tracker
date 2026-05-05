require "application_system_test_case"

class PodFlowTest < ApplicationSystemTestCase
  setup do
    CommanderFormat::CardTagImporter.new.import!
    @user = users(:one)
    @library = Decks::FixtureLibrary.new
    @deck_a = build_deck("krenko_goblin_tribal")
    @deck_b = build_deck("mono_green_omnath_stompy")
    @deck_c = build_deck("atraxa_superfriends_upgraded")
  end

  test "user builds, analyzes, and shares a pod" do
    sign_in_through_ui(@user)

    visit new_pod_path
    fill_in "Pod name", with: "Friday Pod"
    check @deck_a.name
    check @deck_b.name
    check @deck_c.name
    click_button "Analyze pod"

    assert_text "Pod analyzed."
    assert_text "Friday Pod"
    assert_text "Rule 0 brief"
    assert_text "Per-deck scores"
    assert_text @deck_a.name
    assert_text @deck_c.name

    click_button "Create share link"
    assert_text "Pod share link enabled."
    assert_text "Public share link"

    pod = @user.pods.order(:created_at).last
    assert pod.shared?

    using_session(:guest) do
      visit public_pod_path(pod.share_token)
      assert_text "Shared Commander pod"
      assert_text "Friday Pod"
      assert_text "Per-deck scores"
    end
  end

  test "rejects pods with fewer than two decks" do
    sign_in_through_ui(@user)
    visit new_pod_path
    fill_in "Pod name", with: "One-deck pod"
    check @deck_a.name
    click_button "Analyze pod"

    assert_text(/at least/i)
  end

  private
    def build_deck(slug)
      deck = @library.build_deck(slug, user: @user)
      deck.save!
      Decks::Analyzer.run(deck)
      deck
    end

    def sign_in_through_ui(user, password: "password")
      visit new_session_path
      fill_in "email_address", with: user.email_address
      fill_in "password", with: password
      click_button "Sign in"
      assert_text "Ideal Magic"
    end
end
