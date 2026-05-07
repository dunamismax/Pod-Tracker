class DeckAiEvaluationsController < ApplicationController
  def create
    deck = current_user.decks.find(params[:deck_id])
    latest = deck.latest_ai_run
    if latest&.active?
      redirect_to deck_path(deck), notice: "AI evaluation is already #{latest.status}."
      return
    end

    Codex::EvaluationRunner.enqueue_deck!(deck, user: current_user)
    redirect_to deck_path(deck), notice: "AI evaluation queued."
  rescue Codex::EvaluationRunner::QuotaBlocked => error
    redirect_to deck_path(deck), alert: "AI evaluation paused: #{error.message}."
  rescue ArgumentError => error
    redirect_to deck_path(deck), alert: error.message
  end

  private

    def current_user
      Current.session.user
    end
end
