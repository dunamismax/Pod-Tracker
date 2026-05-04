class PodEvaluation < ApplicationRecord
  STATUSES = %w[draft queued running succeeded failed archived].freeze

  belongs_to :user, optional: true

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :deck_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 4 }
end
