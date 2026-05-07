class DeckSharesController < ApplicationController
  before_action :load_deck

  def create
    @deck.issue_share_token!
    record_audit("deck.share_enabled")
    redirect_to deck_path(@deck), notice: "Deck share link enabled."
  end

  def destroy
    @deck.revoke_share!
    record_audit("deck.share_revoked")
    redirect_to deck_path(@deck), notice: "Deck share link revoked."
  end

  private
    def current_user
      Current.session.user
    end

    def load_deck
      @deck = current_user.decks.find(params[:deck_id])
    end

    def record_audit(event_name)
      AuditEvent.create!(
        user: current_user,
        auditable: @deck,
        event_name: event_name,
        occurred_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { deck_id: @deck.id, deck_name: @deck.name }
      )
    end
end
