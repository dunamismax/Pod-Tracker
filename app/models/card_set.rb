class CardSet < ApplicationRecord
  has_many :card_printings, dependent: :restrict_with_exception

  normalizes :code, with: ->(code) { code.to_s.strip.downcase }

  validates :code, :name, presence: true
end
