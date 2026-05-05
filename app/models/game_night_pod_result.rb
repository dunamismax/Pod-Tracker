class GameNightPodResult < ApplicationRecord
  belongs_to :game_night
  belongs_to :winner_player, class_name: "Player", optional: true

  validates :pod_number,
    numericality: { only_integer: true, greater_than_or_equal_to: 1 },
    uniqueness: { scope: :game_night_id }
  validates :turns, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :winner_or_draw

  private

  def winner_or_draw
    return if draw? || winner_player_id.present?

    errors.add(:base, "record a winner or mark the pod as a draw")
  end
end
