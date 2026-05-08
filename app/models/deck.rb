class Deck < ApplicationRecord
  FORMATS = %w[commander].freeze
  STATUSES = %w[draft imported analyzing analyzed failed archived].freeze
  VISIBILITIES = %w[private unlisted public].freeze

  belongs_to :user, optional: true
  belongs_to :guest_for_pod, class_name: "Pod", optional: true
  has_many :deck_cards, dependent: :destroy
  has_many :commanders, dependent: :destroy
  has_many :provider_links, dependent: :destroy
  has_many :pod_slots, dependent: :destroy
  has_many :game_night_decks, dependent: :destroy
  has_many :game_night_pod_seats, dependent: :destroy
  has_many :game_night_invitations, dependent: :nullify
  has_many :analysis_runs, dependent: :destroy
  has_many :matchup_notes, dependent: :destroy
  has_many :audit_events, as: :auditable, dependent: :nullify

  validates :name, presence: true
  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }

  scope :shared, -> { where.not(share_token: nil).where(share_revoked_at: nil) }

  def guest?
    guest_for_pod_id.present?
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

  def latest_deterministic_run
    analysis_runs
      .where(kind: "deterministic", status: "succeeded")
      .order(completed_at: :desc, id: :desc)
      .includes(:scorecard)
      .first
  end

  def latest_ai_run
    analysis_runs
      .where(kind: "ai")
      .recent_first
      .first
  end

  def recompute_deterministic_analysis!
    Decks::Analyzer.run(self)
  end
end
