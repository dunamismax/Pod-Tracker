module GameNights
  class InvitationResponder
    Result = Struct.new(:success, :invitation, :errors, keyword_init: true) do
      alias_method :success?, :success
    end

    def self.accept(invitation, user:, deck:, response_note: nil)
      new(invitation, user: user).accept(deck: deck, response_note: response_note)
    end

    def self.decline(invitation, user:, response_note: nil)
      new(invitation, user: user).decline(response_note: response_note)
    end

    def self.cancel(invitation)
      new(invitation, user: nil).cancel
    end

    def initialize(invitation, user:)
      @invitation = invitation
      @user = user
    end

    def accept(deck:, response_note: nil)
      return failure([ "Invitation is not open." ]) unless can_respond?
      return failure([ "Pick a deck before accepting." ]) unless deck
      return failure([ "Choose one of your own decks." ]) unless deck.user_id == user.id

      GameNightInvitation.transaction do
        clear_prior_acceptance!

        player = find_or_create_player(host_user: invitation.game_night.user, user: user)
        position = next_position
        deck_position = next_deck_position

        invitation.game_night.game_night_players.find_or_create_by!(player: player) do |gnp|
          gnp.position = position
        end

        existing_deck = invitation.game_night.game_night_decks.find_by(player: player)
        if existing_deck
          existing_deck.update!(deck: deck, deck_name_snapshot: deck.name, commander_names_snapshot: deck.commander_names)
        else
          invitation.game_night.game_night_decks.create!(
            player: player,
            deck: deck,
            position: deck_position
          )
        end

        invitation.update!(
          status: "accepted",
          responded_user: user,
          player: player,
          deck: deck,
          response_note: response_note.to_s.strip.presence,
          responded_at: Time.current
        )
      end

      success
    rescue ActiveRecord::RecordInvalid => e
      failure([ e.message ])
    end

    def decline(response_note: nil)
      return failure([ "Invitation is not open." ]) unless can_respond?

      GameNightInvitation.transaction do
        clear_prior_acceptance!
        invitation.update!(
          status: "declined",
          responded_user: user,
          player: nil,
          deck: nil,
          response_note: response_note.to_s.strip.presence,
          responded_at: Time.current
        )
      end

      success
    rescue ActiveRecord::RecordInvalid => e
      failure([ e.message ])
    end

    def cancel
      return failure([ "Invitation already responded to." ]) unless invitation.pending?

      invitation.update!(status: "cancelled", responded_at: Time.current)
      success
    rescue ActiveRecord::RecordInvalid => e
      failure([ e.message ])
    end

    private

    attr_reader :invitation, :user

    def can_respond?
      invitation.pending? || invitation.declined? || invitation.accepted?
    end

    def clear_prior_acceptance!
      return unless invitation.player_id

      prior_player = invitation.player
      game_night = invitation.game_night

      game_night.game_night_pod_seats.where(player_id: prior_player.id).destroy_all
      game_night.game_night_decks.where(player_id: prior_player.id).destroy_all
      game_night.game_night_players.where(player_id: prior_player.id).destroy_all
    end

    def next_position
      (invitation.game_night.game_night_players.maximum(:position) || 0) + 1
    end

    def next_deck_position
      (invitation.game_night.game_night_decks.maximum(:position) || 0) + 1
    end

    def find_or_create_player(host_user:, user:)
      label = user.display_name.presence || invitation.display_name.presence || user.email_address
      normalized = Player.normalize_card_name(label)

      player = host_user.players.find_by(normalized_name: normalized)
      return player if player

      host_user.players.create!(name: label)
    end

    def success
      Result.new(success: true, invitation: invitation, errors: [])
    end

    def failure(errors)
      Result.new(success: false, invitation: invitation, errors: errors)
    end
  end
end
