require "test_helper"
require "rake"

class DemoResetTaskTest < ActiveSupport::TestCase
  DEMO_EMAIL = "demo@demo.com".freeze

  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    [ "demo:reset", "demo:status" ].each { |name| Rake::Task[name].reenable if Rake::Task.task_defined?(name) }

    User.where(email_address: DEMO_EMAIL).destroy_all
    @demo = User.create!(
      email_address: DEMO_EMAIL,
      password: "demo1234",
      timezone: "UTC",
      preferred_units: "imperial",
      email_verified_at: Time.current
    )
  end

  test "demo:reset wipes decks, audit events, and provider links" do
    deck = @demo.decks.create!(
      name: "Demo Atraxa",
      format: "commander",
      status: "imported",
      visibility: "private",
      source_type: "pasted_text",
      commander_names: [ "Atraxa, Praetors' Voice" ],
      last_imported_at: Time.current
    )
    deck.commanders.create!(name: "Atraxa, Praetors' Voice", position: 1)
    deck.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 1)

    @demo.audit_events.create!(event_name: "deck.imported", occurred_at: Time.current, auditable: deck)
    @demo.provider_links.create!(provider: "archidekt", profile_url: "https://archidekt.com/u/demo", handle: "demo")

    capture_io { Rake::Task["demo:reset"].invoke }

    @demo.reload
    assert_equal 0, @demo.decks.count
    assert_equal 0, @demo.provider_links.count
    assert_equal 1, @demo.audit_events.where(event_name: "demo.reset").count
    assert_equal 0, @demo.audit_events.where(event_name: "deck.imported").count
    assert_equal "Demo Player", @demo.display_name
    assert_equal "UTC", @demo.timezone
    assert_equal "imperial", @demo.preferred_units
    assert @demo.email_verified?
  end

  test "demo:reset is a no-op on an already-clean account except for the reset audit event" do
    capture_io { Rake::Task["demo:reset"].invoke }
    assert_equal 1, @demo.audit_events.where(event_name: "demo.reset").count
  end

  test "demo:reset aborts when the demo user does not exist" do
    User.where(email_address: DEMO_EMAIL).destroy_all
    error = assert_raises(SystemExit) do
      capture_io { Rake::Task["demo:reset"].invoke }
    end
    refute error.success?
  end

  test "demo:status prints counts without changing data" do
    @demo.decks.create!(
      name: "Demo deck",
      format: "commander",
      status: "imported",
      visibility: "private",
      source_type: "pasted_text",
      commander_names: [ "Atraxa, Praetors' Voice" ],
      last_imported_at: Time.current
    )
    out, _err = capture_io { Rake::Task["demo:status"].invoke }
    assert_match(/decks:\s+1/, out)
    assert_equal 1, @demo.decks.count
  end
end
