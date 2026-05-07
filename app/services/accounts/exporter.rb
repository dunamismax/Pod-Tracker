module Accounts
  class Exporter
    SCHEMA_VERSION = 2

    def initialize(user, generated_at: Time.current)
      @user = user
      @generated_at = generated_at
    end

    def to_h
      {
        schema_version: SCHEMA_VERSION,
        generated_at: @generated_at.utc.iso8601,
        account: account_payload,
        codex_account: codex_account_payload,
        provider_links: provider_links_payload,
        decks: decks_payload,
        analysis_runs: analysis_runs_payload,
        pods: pods_payload,
        collection: collection_payload,
        game_nights: game_nights_payload,
        matchup_notes: matchup_notes_payload,
        audit_events: audit_events_payload
      }
    end

    def to_json(*)
      JSON.pretty_generate(to_h)
    end

    def filename
      slug = @user.email_address.to_s.gsub(/[^a-z0-9]+/i, "-").downcase.presence || "account"
      stamp = @generated_at.utc.strftime("%Y%m%dT%H%M%SZ")
      "ideal-magic-account-#{slug}-#{stamp}.json"
    end

    private
      def account_payload
        {
          id: @user.id,
          email_address: @user.email_address,
          display_name: @user.display_name,
          timezone: @user.timezone,
          preferred_units: @user.preferred_units,
          email_verified_at: iso(@user.email_verified_at),
          email_verification_sent_at: iso(@user.email_verification_sent_at),
          created_at: iso(@user.created_at),
          updated_at: iso(@user.updated_at)
        }
      end

      def codex_account_payload
        codex_account = @user.codex_account
        return nil unless codex_account
        codex_account.export_payload
      end

      def provider_links_payload
        @user.provider_links.order(:provider, :handle).map(&:export_payload)
      end

      def decks_payload
        @user.decks.includes(:deck_cards, :commanders, :provider_links).order(:id).map do |deck|
          {
            id: deck.id,
            name: deck.name,
            format: deck.format,
            status: deck.status,
            visibility: deck.visibility,
            created_at: iso(deck.created_at),
            updated_at: iso(deck.updated_at),
            commanders: deck.commanders.order(:position, :id).map do |commander|
              {
                id: commander.id,
                name: commander.name,
                normalized_name: commander.normalized_name,
                position: commander.position
              }
            end,
            cards: deck.deck_cards.order(:board, :id).map do |card|
              {
                id: card.id,
                name: card.name,
                normalized_name: card.normalized_name,
                board: card.board,
                quantity: card.quantity
              }
            end,
            provider_links: deck.provider_links.order(:id).map do |link|
              {
                id: link.id,
                provider: link.provider,
                url: link.url,
                external_id: link.external_id,
                slug: link.slug,
                sync_status: link.sync_status,
                last_synced_at: iso(link.last_synced_at)
              }
            end
          }
        end
      end

      def analysis_runs_payload
        @user.analysis_runs.includes(:scorecard).order(:id).map do |run|
          {
            id: run.id,
            deck_id: run.deck_id,
            kind: run.kind,
            status: run.status,
            rubric_version: run.rubric_version,
            ai_model: run.ai_model,
            queued_at: iso(run.queued_at),
            started_at: iso(run.started_at),
            completed_at: iso(run.completed_at),
            failed_at: iso(run.failed_at),
            error_code: run.error_code,
            scorecard: run.scorecard && scorecard_payload(run.scorecard)
          }
        end
      end

      def pods_payload
        @user.pods.includes(:pod_slots).order(:id).map do |pod|
          {
            id: pod.id,
            name: pod.name,
            status: pod.status,
            shared: pod.shared?,
            created_at: iso(pod.created_at),
            updated_at: iso(pod.updated_at),
            slots: pod.pod_slots.order(:position).map do |slot|
              { id: slot.id, position: slot.position, deck_id: slot.deck_id, label: slot.label }
            end
          }
        end
      end

      def collection_payload
        cards = @user.collection_cards.order(:normalized_name, :id).map do |card|
          {
            id: card.id,
            name: card.name,
            normalized_name: card.normalized_name,
            quantity: card.quantity,
            source_type: card.source_type,
            created_at: iso(card.created_at),
            updated_at: iso(card.updated_at)
          }
        end
        imports = @user.collection_imports.order(:id).map do |import|
          {
            id: import.id,
            source_type: import.source_type,
            status: import.status,
            imported_count: import.imported_count,
            unresolved_count: import.unresolved_count,
            created_at: iso(import.created_at),
            updated_at: iso(import.updated_at)
          }
        end
        { cards: cards, imports: imports }
      end

      def game_nights_payload
        @user.game_nights
             .includes(:game_night_players, :game_night_decks, :game_night_pod_seats, :game_night_pod_results)
             .order(:played_on, :id)
             .map do |gn|
          {
            id: gn.id,
            name: gn.name,
            played_on: gn.played_on&.iso8601,
            location: gn.location,
            notes: gn.notes,
            status: gn.status,
            created_at: iso(gn.created_at),
            updated_at: iso(gn.updated_at),
            players: gn.game_night_players.map do |gnp|
              { id: gnp.id, player_id: gnp.player_id, position: gnp.position }
            end,
            decks: gn.game_night_decks.map do |gnd|
              {
                id: gnd.id,
                deck_id: gnd.deck_id,
                player_id: gnd.player_id,
                position: gnd.position,
                deck_name_snapshot: gnd.deck_name_snapshot,
                commander_names_snapshot: gnd.commander_names_snapshot
              }
            end,
            pod_seats: gn.game_night_pod_seats.map do |seat|
              {
                id: seat.id,
                pod_number: seat.pod_number,
                seat_number: seat.seat_number,
                player_id: seat.player_id,
                deck_id: seat.deck_id,
                deck_name_snapshot: seat.deck_name_snapshot,
                commander_names_snapshot: seat.commander_names_snapshot,
                analysis_snapshot: seat.analysis_snapshot
              }
            end,
            pod_results: gn.game_night_pod_results.map do |result|
              {
                id: result.id,
                pod_number: result.pod_number,
                winner_player_id: result.winner_player_id,
                draw: result.draw,
                turns: result.turns,
                win_condition: result.win_condition,
                notes: result.notes
              }
            end
          }
        end
      end

      def matchup_notes_payload
        @user.matchup_notes.order(:happened_at, :id).map do |note|
          {
            id: note.id,
            deck_id: note.deck_id,
            commander_id: note.commander_id,
            opponent_id: note.opponent_id,
            pod_id: note.pod_id,
            game_night_id: note.game_night_id,
            game_night_pod_number: note.game_night_pod_number,
            tags: note.tags,
            body: note.body,
            happened_at: iso(note.happened_at),
            created_at: iso(note.created_at),
            updated_at: iso(note.updated_at)
          }
        end
      end

      def audit_events_payload
        @user.audit_events.order(:occurred_at, :id).map do |event|
          {
            id: event.id,
            event_name: event.event_name,
            auditable_type: event.auditable_type,
            auditable_id: event.auditable_id,
            metadata: event.metadata,
            occurred_at: iso(event.occurred_at),
            ip_address: event.ip_address,
            user_agent: event.user_agent
          }
        end
      end

      def scorecard_payload(scorecard)
        Scorecard::SCORE_COLUMNS.each_with_object({ confidence: scorecard.confidence }) do |column, memo|
          memo[column] = scorecard.public_send(column)
        end
      end

      def iso(value)
        value&.utc&.iso8601
      end
  end
end
