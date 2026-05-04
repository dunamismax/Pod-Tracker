class OracleCard < ApplicationRecord
  has_many :card_printings, dependent: :destroy
  has_many :deck_cards, dependent: :nullify
  has_many :commanders, dependent: :nullify
  has_many :rulings, dependent: :destroy
  has_many :salt_social_friction_evidences, dependent: :nullify

  validates :scryfall_oracle_id, :name, :normalized_name, presence: true

  before_validation :set_normalized_name

  private

  def set_normalized_name
    self.normalized_name = self.class.normalize_card_name(name) if name.present?
  end
end
