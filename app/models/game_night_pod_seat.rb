class GameNightPodSeat < ApplicationRecord
  belongs_to :game_night
  belongs_to :player
  belongs_to :deck
  belongs_to :analysis_run, optional: true

  validates :pod_number, :seat_number,
    numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :seat_number, uniqueness: { scope: [ :game_night_id, :pod_number ] }
  validates :player_id, uniqueness: { scope: :game_night_id }
  validates :deck_name_snapshot, presence: true

  before_validation :snapshot_deck
  before_validation :snapshot_analysis

  private

  def snapshot_deck
    return unless deck
    return if deck_name_snapshot.present?

    self.deck_name_snapshot = deck.name
    self.commander_names_snapshot = deck.commander_names
  end

  def snapshot_analysis
    return unless deck
    return if analysis_snapshot.present?

    run = analysis_run || deck.latest_deterministic_run
    return unless run

    self.analysis_run = run
    scorecard = run.scorecard
    self.analysis_snapshot = {
      "analysis_run_id" => run.id,
      "rubric_version" => run.rubric_version,
      "deck_updated_at" => deck.updated_at&.iso8601,
      "deck_card_count" => deck.deck_cards.sum(:quantity),
      "scorecard" => scorecard_snapshot(scorecard)
    }
  end

  def scorecard_snapshot(scorecard)
    return {} unless scorecard

    {
      "bracket" => scorecard.bracket,
      "bracket_sub_band" => scorecard.bracket_sub_band,
      "bracket_payload" => scorecard.bracket_payload,
      "power_score" => scorecard.power_score,
      "speed_score" => scorecard.speed_score,
      "interaction_score" => scorecard.interaction_score,
      "consistency_score" => scorecard.consistency_score,
      "salt_score" => scorecard.salt_score,
      "social_friction_score" => scorecard.social_friction_score
    }
  end
end
