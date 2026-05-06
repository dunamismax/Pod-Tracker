class UnresolvedEntriesController < ApplicationController
  def update
    entry = current_user.unresolved_entries.find(params[:id])

    if params[:commit] == "Ignore"
      entry.update!(status: "ignored")
      redirect_back fallback_location: collection_path, notice: "Unresolved entry ignored."
      return
    end

    resolved_name = unresolved_entry_params[:name].to_s.strip.presence || entry.name
    oracle_card = find_oracle_card(resolved_name)
    unless oracle_card
      redirect_back fallback_location: collection_path, alert: "Card not found in the Scryfall corpus."
      return
    end

    normalized_name = CollectionCard.normalize_card_name(oracle_card.name)
    card = current_user.collection_cards.find_or_initialize_by(normalized_name:)
    card.name = oracle_card.name
    card.oracle_card = oracle_card
    card.quantity = (card.persisted? ? card.quantity.to_i : 0) + entry.quantity
    card.source_type = "import"
    card.save!
    entry.update!(status: "resolved", name: oracle_card.name)

    redirect_back fallback_location: collection_path, notice: "Unresolved entry added to collection."
  end

  private

    def current_user
      Current.session.user
    end

    def unresolved_entry_params
      params.require(:unresolved_entry).permit(:name)
    end

    def find_oracle_card(name)
      normalized_name = CollectionCard.normalize_card_name(name)
      OracleCard.find_by(normalized_name:)
    end
end
