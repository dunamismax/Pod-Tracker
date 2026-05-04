class CodexLoginAttempt < ApplicationRecord
  AUTH_MODES = %w[chatgpt_browser chatgpt_device_code].freeze
  STATUSES = %w[pending awaiting_user completed cancelled failed expired].freeze
  TERMINAL_STATUSES = %w[completed cancelled failed expired].freeze
  ACTIVE_STATUSES = %w[pending awaiting_user].freeze

  belongs_to :user

  validates :auth_mode, presence: true, inclusion: { in: AUTH_MODES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  before_validation :set_default_started_at

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :recent_first, -> { order(created_at: :desc) }

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def expired?(now: Time.current)
    return false unless expires_at
    return true if status == "expired"
    expires_at <= now
  end

  def mark_awaiting_user!(handle:, login_url: nil, verification_uri: nil, user_code: nil, expires_at: nil, now: Time.current)
    update!(
      status: "awaiting_user",
      external_handle: handle,
      login_url: login_url,
      verification_uri: verification_uri,
      user_code: user_code,
      expires_at: expires_at,
      awaiting_user_at: now
    )
  end

  def mark_completed!(now: Time.current)
    update!(status: "completed", completed_at: now)
  end

  def mark_cancelled!(now: Time.current)
    update!(status: "cancelled", cancelled_at: now)
  end

  def mark_expired!(now: Time.current)
    update!(status: "expired", failed_at: now)
  end

  def mark_failed!(code:, message:, now: Time.current)
    update!(status: "failed", failure_code: code, failure_message: message, failed_at: now)
  end

  def touch_polled!(now: Time.current)
    update!(last_polled_at: now)
  end

  private
    def set_default_started_at
      self.started_at ||= Time.current
    end
end
