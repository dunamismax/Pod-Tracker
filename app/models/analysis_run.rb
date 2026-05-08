class AnalysisRun < ApplicationRecord
  KINDS = %w[deterministic ai combined].freeze
  AI_KINDS = %w[ai combined].freeze
  STATUSES = %w[queued running succeeded failed canceled].freeze

  belongs_to :deck, optional: true
  belongs_to :pod, optional: true
  belongs_to :user, optional: true
  has_one :scorecard, dependent: :destroy
  has_many :salt_social_friction_evidences, dependent: :destroy
  has_many :game_night_pod_seats, dependent: :nullify

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :rubric_version, presence: true
  validates :queued_at, presence: true

  before_validation :set_default_queued_at

  scope :ai_runs, -> { where(kind: AI_KINDS) }
  scope :queued_since, ->(time) { where(queued_at: time..) }
  scope :counted_for_quota, -> { ai_runs.where.not(status: "canceled") }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def ai?
    AI_KINDS.include?(kind)
  end

  def active?
    %w[queued running].include?(status)
  end

  def target
    deck || pod
  end

  def stale?
    return false unless ai? && completed_at

    if deck
      deterministic = deck.latest_deterministic_run
      deterministic&.completed_at && deterministic.completed_at > completed_at
    elsif pod
      deterministic = pod.latest_analysis_run
      deterministic&.completed_at && deterministic.completed_at > completed_at
    else
      false
    end
  end

  def ai_payload
    return {} unless ai_response_snapshot.is_a?(Hash)

    ai_response_snapshot["validated_response"] || ai_response_snapshot["response"] || {}
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
