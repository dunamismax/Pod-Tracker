class Scorecard < ApplicationRecord
  SCORE_COLUMNS = %i[
    power_score
    speed_score
    interaction_score
    consistency_score
    pod_fit_score
    salt_score
    social_friction_score
  ].freeze

  belongs_to :analysis_run

  validates :analysis_run, uniqueness: true
  validates :confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true
  validates(*SCORE_COLUMNS, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  }, allow_nil: true)
end
