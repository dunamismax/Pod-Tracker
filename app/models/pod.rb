class Pod < ApplicationRecord
  STATUSES = %w[draft analyzed failed archived].freeze
  FORMATS = %w[commander].freeze
  MIN_SLOTS = 2
  MAX_SLOTS = 4

  belongs_to :user, optional: true
  has_many :pod_slots, -> { order(:position) }, dependent: :destroy
  has_many :decks, through: :pod_slots
  has_many :pod_analysis_runs, dependent: :destroy
  has_many :audit_events, as: :auditable, dependent: :nullify

  validates :name, presence: true
  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }

  scope :shared, -> { where.not(share_token: nil).where(share_revoked_at: nil) }

  def latest_analysis_run
    pod_analysis_runs.order(created_at: :desc, id: :desc).first
  end

  def shared?
    share_token.present? && share_revoked_at.nil?
  end

  def issue_share_token!
    return share_token if shared?

    update!(
      share_token: SecureRandom.urlsafe_base64(16),
      shared_at: Time.current,
      share_revoked_at: nil
    )
    share_token
  end

  def revoke_share!
    return unless share_token.present?

    update!(share_revoked_at: Time.current)
  end
end
