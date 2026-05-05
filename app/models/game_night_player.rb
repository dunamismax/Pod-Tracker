class GameNightPlayer < ApplicationRecord
  belongs_to :game_night
  belongs_to :player

  validates :position,
    numericality: { only_integer: true, greater_than_or_equal_to: 1 },
    uniqueness: { scope: :game_night_id }
  validates :player_id, uniqueness: { scope: :game_night_id }
end
