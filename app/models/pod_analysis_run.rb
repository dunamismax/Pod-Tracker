class PodAnalysisRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed].freeze

  belongs_to :pod
  belongs_to :user, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :rubric_version, presence: true
end
