class Deck < ApplicationRecord
  FORMATS = %w[commander].freeze
  STATUSES = %w[draft imported analyzing analyzed failed archived].freeze
  VISIBILITIES = %w[private unlisted public].freeze

  belongs_to :user, optional: true
  belongs_to :guest_for_pod, class_name: "Pod", optional: true
  has_many :deck_cards, dependent: :destroy
  has_many :commanders, dependent: :destroy
  has_many :provider_links, dependent: :destroy
  has_many :analysis_runs, dependent: :destroy
  has_many :matchup_notes, dependent: :destroy
  has_many :audit_events, as: :auditable, dependent: :nullify

  validates :name, presence: true
  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }

  def guest?
    guest_for_pod_id.present?
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
