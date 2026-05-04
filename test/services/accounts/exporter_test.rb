require "test_helper"

module Accounts
  class ExporterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
    end

    test "serializes account fields with iso8601 timestamps" do
      payload = Exporter.new(@user).to_h

      assert_equal Exporter::SCHEMA_VERSION, payload[:schema_version]
      assert_match(/\AZ?\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, payload[:generated_at])
      assert_equal @user.email_address, payload[:account][:email_address]
      assert_equal @user.timezone, payload[:account][:timezone]
    end

    test "includes decks with cards, commanders, and provider links" do
      deck = @user.decks.create!(name: "Kinnan Test Deck")
      deck.commanders.create!(name: "Kinnan, Bonder Prodigy", position: 1)
      deck.deck_cards.create!(name: "Sol Ring", quantity: 1)
      deck.provider_links.create!(provider: "moxfield", external_id: "abc", url: "https://moxfield.com/decks/abc")

      payload = Exporter.new(@user).to_h
      decks = payload[:decks]

      assert_equal 1, decks.size
      assert_equal "Kinnan Test Deck", decks.first[:name]
      assert_equal "Kinnan, Bonder Prodigy", decks.first[:commanders].first[:name]
      assert_equal "Sol Ring", decks.first[:cards].first[:name]
      assert_equal "moxfield", decks.first[:provider_links].first[:provider]
    end

    test "includes analysis runs with scorecards" do
      deck = @user.decks.create!(name: "Doomed Deck")
      run = @user.analysis_runs.create!(deck: deck, rubric_version: "2026-05-03")
      run.create_scorecard!(power_score: 50, speed_score: 50, interaction_score: 50, consistency_score: 50, confidence: 0.5)

      payload = Exporter.new(@user).to_h

      assert_equal 1, payload[:analysis_runs].size
      assert_equal 50, payload[:analysis_runs].first[:scorecard][:power_score]
    end

    test "includes audit events tied to the user" do
      AuditEvent.create!(user: @user, event_name: "deck.imported", metadata: { source: "paste" })

      payload = Exporter.new(@user).to_h
      names = payload[:audit_events].map { |e| e[:event_name] }

      assert_includes names, "deck.imported"
    end

    test "to_json returns parseable JSON with the full payload" do
      json = Exporter.new(@user).to_json
      parsed = JSON.parse(json)

      assert_equal Exporter::SCHEMA_VERSION, parsed["schema_version"]
      assert_equal @user.email_address, parsed["account"]["email_address"]
    end

    test "filename slug uses email and a timestamp" do
      generated_at = Time.utc(2026, 5, 4, 12, 30, 0)
      filename = Exporter.new(@user, generated_at: generated_at).filename

      assert_match(/^ideal-magic-account-.+-20260504T123000Z\.json$/, filename)
    end
  end
end
