class CollectionCardsController < ApplicationController
  def create
    name = collection_card_params[:name].to_s.strip
    quantity = collection_card_params[:quantity].to_i
    quantity = 1 if quantity <= 0

    oracle_card = find_oracle_card(name)
    unless oracle_card
      redirect_to collection_path, alert: "Card not found in the Scryfall corpus."
      return
    end

    normalized_name = CollectionCard.normalize_card_name(oracle_card.name)
    card = current_user.collection_cards.find_or_initialize_by(normalized_name:)
    card.name = oracle_card.name
    card.oracle_card = oracle_card
    card.quantity = (card.persisted? ? card.quantity.to_i : 0) + quantity
    card.source_type = "manual"
    card.save!

    redirect_to collection_path, notice: "Collection updated."
  end

  def update
    card = current_user.collection_cards.find(params[:id])
    quantity = collection_card_params[:quantity].to_i

    if quantity.positive?
      card.update!(quantity:)
      redirect_to collection_path, notice: "Collection updated."
    else
      card.destroy!
      redirect_to collection_path, notice: "Card removed from collection."
    end
  end

  def destroy
    card = current_user.collection_cards.find(params[:id])
    card.destroy!
    redirect_to collection_path, notice: "Card removed from collection."
  end

  private

    def current_user
      Current.session.user
    end

    def collection_card_params
      params.require(:collection_card).permit(:name, :quantity)
    end

    def find_oracle_card(name)
      normalized_name = CollectionCard.normalize_card_name(name)
      OracleCard.find_by(normalized_name:)
    end
end
