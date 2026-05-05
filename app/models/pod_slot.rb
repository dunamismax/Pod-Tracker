class PodSlot < ApplicationRecord
  belongs_to :pod
  belongs_to :deck

  validates :position,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: Pod::MAX_SLOTS },
    uniqueness: { scope: :pod_id }
end
