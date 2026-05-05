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

  BRACKETS = (1..5).to_a.freeze
  SUB_BANDS = %w[low mid high].freeze

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
  validates :bracket, inclusion: { in: BRACKETS }, allow_nil: true
  validates :bracket_sub_band, inclusion: { in: SUB_BANDS }, allow_nil: true
end
