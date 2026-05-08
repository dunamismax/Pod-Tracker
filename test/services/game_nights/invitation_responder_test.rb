require "test_helper"

module GameNights
  class InvitationResponderTest < ActiveSupport::TestCase
    setup do
      @host = users(:one)
      @invitee = users(:two)
      @game_night = @host.game_nights.create!(name: "Friday", played_on: Date.new(2026, 5, 5))
      @invitee_deck = @invitee.decks.create!(name: "Atraxa Counters", commander_names: [ "Atraxa, Praetors' Voice" ])
      @invitation = @game_night.game_night_invitations.create!(
        email_address: @invitee.email_address,
        display_name: "Two",
        position: 1
      )
    end

    test "accept registers a player + deck for the invitee" do
      result = nil
      assert_difference -> { GameNightPlayer.count } => 1,
                        -> { GameNightDeck.count } => 1,
                        -> { Player.where(user: @host).count } => 1 do
        result = InvitationResponder.accept(@invitation, user: @invitee, deck: @invitee_deck)
      end

      assert result.success?, result.errors.to_sentence
      @invitation.reload
      assert @invitation.accepted?
      assert_equal @invitee, @invitation.responded_user
      assert_equal @invitee_deck, @invitation.deck
      assert @invitation.player.present?
      assert_equal @host.id, @invitation.player.user_id

      gn_deck = @game_night.game_night_decks.find_by(player: @invitation.player)
      assert_equal @invitee_deck, gn_deck.deck
      assert_equal "Atraxa Counters", gn_deck.deck_name_snapshot
    end

    test "accept rejects another user's deck" do
      stranger_deck = users(:one).decks.create!(name: "Krenko", commander_names: [ "Krenko, Mob Boss" ])
      result = InvitationResponder.accept(@invitation, user: @invitee, deck: stranger_deck)
      assert_not result.success?
    end

    test "decline marks the invitation declined" do
      InvitationResponder.accept(@invitation, user: @invitee, deck: @invitee_deck)
      assert_equal 1, @game_night.game_night_decks.count

      result = InvitationResponder.decline(@invitation, user: @invitee, response_note: "Sick")
      assert result.success?
      @invitation.reload
      assert @invitation.declined?
      assert_equal "Sick", @invitation.response_note
      # Prior acceptance side effects undone
      assert_equal 0, @game_night.game_night_decks.count
      assert_equal 0, @game_night.game_night_players.count
    end

    test "cancel only works on pending invitations" do
      result = InvitationResponder.cancel(@invitation)
      assert result.success?
      assert @invitation.reload.cancelled?

      result = InvitationResponder.cancel(@invitation)
      assert_not result.success?
    end
  end
end
