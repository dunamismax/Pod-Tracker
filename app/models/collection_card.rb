class CollectionCard < ApplicationRecord
  SOURCE_TYPES = %w[manual import].freeze

  belongs_to :user
  belongs_to :oracle_card, optional: true
  belongs_to :card_printing, optional: true

  validates :name, :normalized_name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :normalized_name, uniqueness: { scope: :user_id }

  before_validation :set_normalized_name

  private

    def set_normalized_name
      self.normalized_name = self.class.normalize_card_name(name) if name.present?
    end
end
