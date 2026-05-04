class AnalysisRun < ApplicationRecord
  KINDS = %w[deterministic ai combined].freeze
  STATUSES = %w[queued running succeeded failed canceled].freeze

  belongs_to :deck, optional: true
  belongs_to :user, optional: true
  has_one :scorecard, dependent: :destroy
  has_many :salt_social_friction_evidences, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :rubric_version, presence: true
  validates :queued_at, presence: true

  before_validation :set_default_queued_at

  private

  def set_default_queued_at
    self.queued_at ||= Time.current
  end
end
