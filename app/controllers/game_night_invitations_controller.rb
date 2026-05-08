class GameNightInvitationsController < ApplicationController
  before_action :load_host_game_night, only: %i[create destroy resend]
  before_action :load_invitation_for_host, only: %i[destroy resend]
  before_action :load_invitation_by_token, only: %i[show accept decline]

  # Host: bulk-add invitations to a game night they own.
  def create
    rows = normalize_invite_rows(invite_params)
    message = params.dig(:invitations, :message).to_s.strip
    if message.present?
      rows = rows.map { |row| row.merge("message" => message) }
    end

    result = GameNights::Inviter.call(@game_night, rows: rows, host: current_user)

    if result.success? && result.invitations.any?
      record_audit("game_night.invitations_sent", count: result.invitations.size)
      redirect_to game_night_path(@game_night), notice: invite_notice(result.invitations.size)
    elsif result.success?
      redirect_to game_night_path(@game_night), alert: "Add an email address before sending invites."
    else
      redirect_to game_night_path(@game_night), alert: result.errors.to_sentence
    end
  end

  # Host: cancel a pending invitation.
  def destroy
    GameNights::InvitationResponder.cancel(@invitation)
    record_audit("game_night.invitation_cancelled", invitation_id: @invitation.id)
    redirect_to game_night_path(@game_night), notice: "Invitation cancelled."
  end

  # Host: resend invitation email.
  def resend
    GameNightMailer.invitation(@invitation).deliver_later
    @invitation.update!(reminded_at: Time.current)
    record_audit("game_night.invitation_resent", invitation_id: @invitation.id)
    redirect_to game_night_path(@game_night), notice: "Invitation resent to #{@invitation.email_address}."
  end

  # Invitee: view the invitation.
  def show
    return reject_wrong_user unless invitee_match?

    @game_night = @invitation.game_night
    @decks = current_user.decks.order(updated_at: :desc).limit(100)
    @selected_deck_id = @invitation.deck_id
  end

  # Invitee: accept invitation with a chosen deck.
  def accept
    return reject_wrong_user unless invitee_match?

    deck = current_user.decks.find_by(id: params[:deck_id])
    response_note = params[:response_note]

    result = GameNights::InvitationResponder.accept(
      @invitation,
      user: current_user,
      deck: deck,
      response_note: response_note
    )

    if result.success?
      record_invitation_audit("game_night.invitation_accepted")
      redirect_to invitation_response_path(token: @invitation.token),
                  notice: "You're in. Deck registered for #{@invitation.game_night.name}."
    else
      flash.now[:alert] = result.errors.to_sentence
      @game_night = @invitation.game_night
      @decks = current_user.decks.order(updated_at: :desc).limit(100)
      @selected_deck_id = params[:deck_id]
      render :show, status: :unprocessable_entity
    end
  end

  # Invitee: decline invitation.
  def decline
    return reject_wrong_user unless invitee_match?

    result = GameNights::InvitationResponder.decline(
      @invitation,
      user: current_user,
      response_note: params[:response_note]
    )

    if result.success?
      record_invitation_audit("game_night.invitation_declined")
      redirect_to invitation_response_path(token: @invitation.token),
                  notice: "Declined. The host will see your reply."
    else
      redirect_to invitation_response_path(token: @invitation.token),
                  alert: result.errors.to_sentence
    end
  end

  private

  def current_user
    Current.session.user
  end

  def load_host_game_night
    @game_night = current_user.game_nights.find(params[:game_night_id])
  end

  def load_invitation_for_host
    @invitation = @game_night.game_night_invitations.find(params[:id])
  end

  def load_invitation_by_token
    @invitation = GameNightInvitation.find_by!(token: params[:token])
  end

  def invitee_match?
    @invitation.matches_user?(current_user)
  end

  def reject_wrong_user
    redirect_to game_nights_path,
                alert: "That invitation was sent to a different email address. Sign in with #{@invitation.email_address} to respond."
  end

  def invite_params
    params.fetch(:invitations, ActionController::Parameters.new)
          .permit(rows: %i[email_address display_name message])
          .fetch(:rows, [])
  end

  def normalize_invite_rows(rows)
    case rows
    when ActionController::Parameters
      rows.to_unsafe_h.values.map { |row| row.to_h.transform_keys(&:to_s) }
    when Hash
      rows.values.map { |row| row.to_h.transform_keys(&:to_s) }
    when Array
      rows.map { |row| row.to_h.transform_keys(&:to_s) }
    else
      []
    end
  end

  def invite_notice(count)
    if count == 1
      "Invitation sent."
    else
      "#{count} invitations sent."
    end
  end

  def record_audit(event_name, **metadata)
    AuditEvent.create!(
      user: current_user,
      auditable: @game_night,
      event_name: event_name,
      occurred_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: { session_name: @game_night.name }.merge(metadata)
    )
  end

  def record_invitation_audit(event_name)
    AuditEvent.create!(
      user: current_user,
      auditable: @invitation.game_night,
      event_name: event_name,
      occurred_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        session_name: @invitation.game_night.name,
        invitation_id: @invitation.id
      }
    )
  end
end
