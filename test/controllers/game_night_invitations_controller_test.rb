require "test_helper"

class GameNightInvitationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @host = users(:one)
    @invitee = users(:two)
    @game_night = @host.game_nights.create!(name: "Friday", played_on: Date.new(2026, 5, 5))
  end

  test "host can create invitations and email is queued" do
    sign_in_as(@host)

    assert_difference -> { GameNightInvitation.count } => 1,
                      -> { ActionMailer::Base.deliveries.size } => 1,
                      -> { AuditEvent.where(event_name: "game_night.invitations_sent").count } => 1 do
      ActionMailer::Base.deliveries.clear
      post game_night_invitations_path(@game_night), params: {
        invitations: {
          rows: { "0" => { email_address: "two@example.com", display_name: "Two" } },
          message: "Bring snacks."
        }
      }
      perform_enqueued_jobs
    end

    invitation = GameNightInvitation.last
    assert_equal "two@example.com", invitation.email_address
    assert_equal @invitee, invitation.invited_user
    assert_redirected_to game_night_path(@game_night)
  end

  test "host cannot reach another host's game night invitations endpoint" do
    sign_in_as(@invitee)
    post game_night_invitations_path(@game_night), params: {
      invitations: { rows: { "0" => { email_address: "alice@example.com" } } }
    }
    assert_response :not_found
  end

  test "invitee can view, accept and update their deck" do
    invitation = @game_night.game_night_invitations.create!(email_address: @invitee.email_address, position: 1)
    deck = @invitee.decks.create!(name: "Atraxa", commander_names: [ "Atraxa, Praetors' Voice" ])

    sign_in_as(@invitee)
    get invitation_response_path(token: invitation.token)
    assert_response :success
    assert_select "h1", /Friday/

    assert_difference -> { GameNightDeck.count } => 1 do
      patch accept_invitation_response_path(token: invitation.token), params: { deck_id: deck.id }
    end
    assert_redirected_to invitation_response_path(token: invitation.token)
    assert invitation.reload.accepted?
    assert_equal deck, invitation.deck
  end

  test "invitee with mismatched email is bounced back" do
    invitation = @game_night.game_night_invitations.create!(email_address: "someone@else.com", position: 1)
    sign_in_as(@invitee)
    get invitation_response_path(token: invitation.token)
    assert_redirected_to game_nights_path
  end

  test "invitee can decline and clear an earlier acceptance" do
    invitation = @game_night.game_night_invitations.create!(email_address: @invitee.email_address, position: 1)
    deck = @invitee.decks.create!(name: "Atraxa", commander_names: [ "Atraxa, Praetors' Voice" ])
    GameNights::InvitationResponder.accept(invitation, user: @invitee, deck: deck)
    assert_equal 1, @game_night.game_night_decks.count

    sign_in_as(@invitee)
    patch decline_invitation_response_path(token: invitation.token), params: { response_note: "Conflict" }
    assert_redirected_to invitation_response_path(token: invitation.token)
    assert invitation.reload.declined?
    assert_equal 0, @game_night.game_night_decks.count
  end

  test "host can resend and cancel pending invitations" do
    invitation = @game_night.game_night_invitations.create!(email_address: "two@example.com", position: 1)

    sign_in_as(@host)
    assert_difference -> { ActionMailer::Base.deliveries.size } => 1 do
      ActionMailer::Base.deliveries.clear
      post resend_game_night_invitation_path(@game_night, invitation)
      perform_enqueued_jobs
    end
    assert invitation.reload.reminded_at.present?

    delete game_night_invitation_path(@game_night, invitation)
    assert invitation.reload.cancelled?
  end
end
