class SaltSocialFrictionEvidence < ApplicationRecord
  EVIDENCE_TYPES = %w[salt social_friction rule_zero].freeze

  belongs_to :analysis_run
  belongs_to :deck_card, optional: true
  belongs_to :oracle_card, optional: true
  belongs_to :card_printing, optional: true

  validates :evidence_type, inclusion: { in: EVIDENCE_TYPES }
  validates :category, :label, presence: true
end
