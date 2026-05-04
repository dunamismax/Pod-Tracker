class Ruling < ApplicationRecord
  belongs_to :oracle_card, optional: true
  belongs_to :card_printing, optional: true

  validates :source, :source_id, :comment, presence: true
end
