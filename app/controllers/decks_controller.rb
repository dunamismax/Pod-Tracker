class DecksController < ApplicationController
  rate_limit to: 30, within: 5.minutes, only: :create,
             with: -> { redirect_to new_deck_path, alert: "Too many imports. Try again shortly." }

  before_action :load_deck, only: %i[show destroy]

  def index
    @decks = current_user.decks.order(updated_at: :desc).limit(50)
  end

  def show
  end

  def new
    @form = DeckImportForm.new
  end

  def create
    @form = DeckImportForm.new(import_params)

    unless @form.valid?
      render :new, status: :unprocessable_entity
      return
    end

    result = Decks::Importer.import_pasted_text(
      user: current_user,
      payload: @form.decklist,
      name: @form.name,
      commander_hint: @form.commander_hint
    )

    if result.success?
      record_audit("deck.imported", deck: result.deck, parsed: result.parsed)
      redirect_to deck_path(result.deck), notice: "Deck imported."
    else
      @form.errors.add(:decklist, result.error_messages.first || "Could not import decklist.")
      result.error_messages.drop(1).each { |message| @form.errors.add(:decklist, message) }
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @deck.destroy
    record_audit("deck.removed", deck: @deck, parsed: nil)
    redirect_to decks_path, notice: "Deck removed."
  end

  private
    def current_user
      Current.session.user
    end

    def load_deck
      @deck = current_user.decks.find(params[:id])
    end

    def import_params
      params.require(:deck_import_form).permit(:decklist, :name, :commander_hint)
    end

    def record_audit(name, deck:, parsed:)
      metadata = {}
      if deck
        metadata[:deck_name] = deck.name
        metadata[:source_type] = deck.source_type
        metadata[:card_count] = deck.deck_cards.sum(&:quantity) if deck.respond_to?(:deck_cards)
      end
      if parsed
        metadata[:unparsed_line_count] = parsed.unparsed_lines.size
      end
      AuditEvent.create!(
        user: current_user,
        auditable: deck,
        event_name: name,
        occurred_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: metadata.compact
      )
    end
end
