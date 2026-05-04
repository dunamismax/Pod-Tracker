class DeckCard < ApplicationRecord
  BOARDS = %w[main commander sideboard maybeboard companion].freeze

  belongs_to :deck
  belongs_to :oracle_card, optional: true
  belongs_to :card_printing, optional: true

  validates :name, :normalized_name, presence: true
  validates :board, inclusion: { in: BOARDS }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  before_validation :set_normalized_name

  private

  def set_normalized_name
    self.normalized_name = self.class.normalize_card_name(name) if name.present?
  end
end
