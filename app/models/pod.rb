class Pod < ApplicationRecord
  STATUSES = %w[draft analyzed failed archived].freeze
  FORMATS = %w[commander].freeze
  MIN_SLOTS = 2
  MAX_SLOTS = 4

  belongs_to :user, optional: true
  has_many :pod_slots, -> { order(:position) }, dependent: :destroy
  has_many :decks, through: :pod_slots
  has_many :pod_analysis_runs, dependent: :destroy
  has_many :analysis_runs, dependent: :destroy
  has_many :matchup_notes, dependent: :nullify
  has_many :audit_events, as: :auditable, dependent: :nullify
  has_many :guest_decks,
           class_name: "Deck",
           foreign_key: :guest_for_pod_id,
           inverse_of: :guest_for_pod,
           dependent: :destroy

  validates :name, presence: true
  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }

  scope :shared, -> { where.not(share_token: nil).where(share_revoked_at: nil) }

  def latest_analysis_run
    pod_analysis_runs.order(created_at: :desc, id: :desc).first
  end

  def latest_ai_run
    analysis_runs
      .where(kind: "ai")
      .recent_first
      .first
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
