require "test_helper"

class PodFormTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @decks = 4.times.map do |i|
      Deck.create!(user: @user, name: "Deck #{i + 1}", format: "commander", status: "imported", visibility: "private")
    end
  end

  test "valid with 2-4 owned distinct decks" do
    form = PodForm.new(name: "Pod", deck_ids: @decks.first(3).map(&:id).map(&:to_s))
    form.user = @user
    assert form.valid?, form.errors.full_messages.inspect
  end

  test "rejects fewer than minimum decks" do
    form = PodForm.new(name: "Pod", deck_ids: [ @decks.first.id.to_s ])
    form.user = @user
    assert_not form.valid?
    assert_match(/at least/, form.errors[:deck_ids].first.to_s)
  end

  test "rejects more than maximum decks" do
    extra = Deck.create!(user: @user, name: "Deck 5", format: "commander", status: "imported", visibility: "private")
    form = PodForm.new(name: "Pod", deck_ids: (@decks + [ extra ]).map(&:id).map(&:to_s))
    form.user = @user
    assert_not form.valid?
    assert_match(/at most/, form.errors[:deck_ids].first.to_s)
  end

  test "rejects duplicate decks" do
    form = PodForm.new(name: "Pod", deck_ids: [ @decks.first.id.to_s, @decks.first.id.to_s ])
    form.user = @user
    assert_not form.valid?
    assert_match(/distinct/, form.errors[:deck_ids].first.to_s)
  end

  test "rejects decks not owned by user" do
    other = User.create!(email_address: "other@example.com", password: "password123")
    others_deck = Deck.create!(user: other, name: "Other deck", format: "commander", status: "imported", visibility: "private")
    form = PodForm.new(name: "Pod", deck_ids: [ @decks.first.id.to_s, others_deck.id.to_s ])
    form.user = @user
    assert_not form.valid?
    assert_match(/not owned/, form.errors[:deck_ids].first.to_s)
  end

  test "name is required" do
    form = PodForm.new(name: "  ", deck_ids: @decks.first(2).map(&:id).map(&:to_s))
    form.user = @user
    assert_not form.valid?
    assert_match(/required/, form.errors[:name].first.to_s)
  end

  test "slot_label_for reads keyed labels" do
    form = PodForm.new(name: "Pod", deck_ids: [ "1", "2" ], slot_labels: { "1" => "Alice", "2" => "Bob" })
    assert_equal "Alice", form.slot_label_for(1)
    assert_equal "Bob", form.slot_label_for("2")
    assert_equal "", form.slot_label_for(99)
  end

  test "guest_deck counts toward minimum slot count" do
    form = PodForm.new(
      name: "Pod",
      deck_ids: [ @decks.first.id.to_s ],
      guest_deck: { decklist: "1 Sol Ring" }
    )
    form.user = @user
    assert form.guest_deck_provided?
    assert_equal 2, form.total_slot_count
    assert form.valid?, form.errors.full_messages.inspect
  end

  test "guest_deck plus four owned decks exceeds the maximum slot count" do
    form = PodForm.new(
      name: "Pod",
      deck_ids: @decks.map(&:id).map(&:to_s),
      guest_deck: { decklist: "1 Sol Ring" }
    )
    form.user = @user
    assert_not form.valid?
    assert_match(/at most/, form.errors[:deck_ids].first.to_s)
  end

  test "guest_deck rejects multiple sources" do
    form = PodForm.new(
      name: "Pod",
      deck_ids: @decks.first(2).map(&:id).map(&:to_s),
      guest_deck: {
        decklist: "1 Sol Ring",
        archidekt_url: "https://archidekt.com/decks/123"
      }
    )
    form.user = @user
    assert_not form.valid?
    assert_match(/only one of/, form.errors[:guest_deck].first.to_s)
  end

  test "guest_source picks the supplied source" do
    moxfield_form = PodForm.new(guest_deck: { moxfield_url: "https://moxfield.com/decks/abc" })
    archidekt_form = PodForm.new(guest_deck: { archidekt_url: "https://archidekt.com/decks/12345" })
    pasted_form = PodForm.new(guest_deck: { decklist: "1 Sol Ring" })
    blank_form = PodForm.new(guest_deck: { decklist: "  " })

    assert_equal :moxfield, moxfield_form.guest_source
    assert_equal :archidekt, archidekt_form.guest_source
    assert_equal :pasted, pasted_form.guest_source
    assert_nil blank_form.guest_source
    assert_not blank_form.guest_deck_provided?
  end
end
