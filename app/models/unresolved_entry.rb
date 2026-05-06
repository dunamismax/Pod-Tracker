class UnresolvedEntry < ApplicationRecord
  STATUSES = %w[open resolved ignored].freeze

  belongs_to :user
  belongs_to :collection_import

  validates :status, inclusion: { in: STATUSES }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :reason, :raw_line, presence: true

  before_validation :set_normalized_name

  private

    def set_normalized_name
      self.normalized_name = self.class.normalize_card_name(name) if name.present?
    end
end
