class AnalysisRun < ApplicationRecord
  KINDS = %w[deterministic ai combined].freeze
  AI_KINDS = %w[ai combined].freeze
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

  scope :ai_runs, -> { where(kind: AI_KINDS) }
  scope :queued_since, ->(time) { where(queued_at: time..) }
  scope :counted_for_quota, -> { ai_runs.where.not(status: "canceled") }

  def ai?
    AI_KINDS.include?(kind)
  end

  def mark_started!(now: Time.current)
    update!(status: "running", started_at: now)
  end

  def mark_succeeded!(now: Time.current, codex_rate_limit_snapshot: nil)
    attrs = { status: "succeeded", completed_at: now }
    attrs[:codex_rate_limit_snapshot] = codex_rate_limit_snapshot if codex_rate_limit_snapshot
    attrs[:latency_ms] = elapsed_ms(now) if started_at
    update!(attrs)
  end

  def mark_failed!(code:, message: nil, now: Time.current)
    attrs = { status: "failed", failed_at: now, error_code: code, error_message: message }
    attrs[:latency_ms] = elapsed_ms(now) if started_at
    update!(attrs)
  end

  private

  def set_default_queued_at
    self.queued_at ||= Time.current
  end

  def elapsed_ms(now)
    ((now - started_at) * 1000).round
  end
end
