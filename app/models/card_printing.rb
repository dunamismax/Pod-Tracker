class CardPrinting < ApplicationRecord
  belongs_to :oracle_card
  belongs_to :card_set
  has_many :deck_cards, dependent: :nullify
  has_many :commanders, dependent: :nullify
  has_many :rulings, dependent: :destroy

  validates :scryfall_id, :lang, :name, :normalized_name, :collector_number, presence: true

  before_validation :set_normalized_name

  private

  def set_normalized_name
    self.normalized_name = self.class.normalize_card_name(name) if name.present?
  end
end
