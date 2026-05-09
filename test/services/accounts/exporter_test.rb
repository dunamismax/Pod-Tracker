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

      assert_match(/^pod-tracker-account-.+-20260504T123000Z\.json$/, filename)
    end

    test "includes codex_account metadata without leaking credentials" do
      @user.codex_account&.destroy
      @user.create_codex_account!(
        auth_mode: "chatgpt_browser",
        status: "connected",
        displayed_email: "one-codex@example.com",
        plan_type: "ChatGPT Plus",
        encrypted_credential_payload: "secret-token",
        credential_metadata: { token_kind: "chatgpt_session" },
        rate_limit_snapshot: { primary_used_percent: 5 }
      )

      payload = Exporter.new(@user).to_h
      codex = payload[:codex_account]

      assert_equal "chatgpt_browser", codex[:auth_mode]
      assert_equal "connected", codex[:status]
      assert_equal "one-codex@example.com", codex[:displayed_email]
      assert_equal "ChatGPT Plus", codex[:plan_type]
      assert_equal({ "primary_used_percent" => 5 }, codex[:rate_limit_snapshot])
      assert codex[:credential_present]
      assert_equal [ "token_kind" ], codex[:credential_metadata_keys]

      json = Exporter.new(@user).to_json
      refute_includes json, "secret-token"
    end

    test "codex_account is nil when no codex account is linked" do
      @user.codex_account&.destroy
      payload = Exporter.new(@user).to_h
      assert_nil payload[:codex_account]
    end

    test "includes user provider links ordered by provider and handle" do
      @user.provider_links.create!(
        provider: "moxfield",
        handle: "PlayerOne",
        profile_url: "https://moxfield.com/users/PlayerOne",
        label: "Main"
      )
      @user.provider_links.create!(
        provider: "archidekt",
        handle: "thedude",
        profile_url: "https://archidekt.com/u/thedude"
      )

      payload = Exporter.new(@user).to_h
      links = payload[:provider_links]

      assert_equal 2, links.size
      assert_equal "archidekt", links.first[:provider]
      assert_equal "moxfield", links.last[:provider]
      assert_equal "Main", links.last[:label]
    end

    test "provider_links payload is empty when none are linked" do
      payload = Exporter.new(@user).to_h
      assert_equal [], payload[:provider_links]
    end

    test "includes collection cards and import history" do
      @user.collection_cards.create!(
        name: "Sol Ring",
        normalized_name: "sol ring",
        quantity: 2,
        source_type: "manual"
      )
      @user.collection_imports.create!(
        source_type: "pasted_text",
        status: "completed",
        imported_count: 1,
        unresolved_count: 0
      )

      payload = Exporter.new(@user).to_h

      assert_equal 1, payload[:collection][:cards].size
      assert_equal "Sol Ring", payload[:collection][:cards].first[:name]
      assert_equal 2, payload[:collection][:cards].first[:quantity]
      assert_equal 1, payload[:collection][:imports].size
      assert_equal "completed", payload[:collection][:imports].first[:status]
    end

    test "includes game nights with players, decks, seats, and results" do
      deck = @user.decks.create!(name: "Atraxa", format: "commander", status: "imported", visibility: "private", source_type: "pasted_text")
      deck.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 1)
      player = @user.players.create!(name: "Friend")
      gn = @user.game_nights.create!(name: "Tuesday", played_on: Date.new(2026, 5, 1), status: "completed")
      gn.game_night_players.create!(player: player, position: 1)
      gn.game_night_decks.create!(deck: deck, player: player, position: 1, deck_name_snapshot: deck.name)
      gn.game_night_pod_seats.create!(player: player, deck: deck, pod_number: 1, seat_number: 1)
      gn.game_night_pod_results.create!(pod_number: 1, draw: false, winner_player: player, turns: 8)

      payload = Exporter.new(@user).to_h
      gn_payload = payload[:game_nights].first

      assert_equal "Tuesday", gn_payload[:name]
      assert_equal "2026-05-01", gn_payload[:played_on]
      assert_equal 1, gn_payload[:players].size
      assert_equal 1, gn_payload[:decks].size
      assert_equal 1, gn_payload[:pod_seats].size
      assert_equal 1, gn_payload[:pod_results].size
      assert_equal player.id, gn_payload[:pod_results].first[:winner_player_id]
    end

    test "includes matchup notes scoped to the user" do
      deck = @user.decks.create!(name: "Atraxa", format: "commander", status: "imported", visibility: "private", source_type: "pasted_text")
      @user.matchup_notes.create!(
        deck: deck,
        body: "Won game two on a hard cast Craterhoof.",
        happened_at: Time.zone.local(2026, 5, 4, 21),
        tag_list: "win, late-game"
      )

      payload = Exporter.new(@user).to_h
      note_payload = payload[:matchup_notes].first

      assert_equal "Won game two on a hard cast Craterhoof.", note_payload[:body]
      assert_includes note_payload[:tags], "win"
      assert_includes note_payload[:tags], "late game"
    end
  end
end
