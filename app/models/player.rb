class Player < ApplicationRecord
  belongs_to :user
  has_many :game_night_players, dependent: :destroy
  has_many :game_nights, through: :game_night_players
  has_many :game_night_decks, dependent: :destroy
  has_many :game_night_pod_seats, dependent: :destroy
  has_many :matchup_notes_as_opponent,
           class_name: "MatchupNote",
           foreign_key: :opponent_id,
           dependent: :nullify,
           inverse_of: :opponent
  has_many :won_game_night_pod_results,
           class_name: "GameNightPodResult",
           foreign_key: :winner_player_id,
           dependent: :nullify,
           inverse_of: :winner_player

  validates :name, :normalized_name, presence: true
  validates :normalized_name, uniqueness: { scope: :user_id }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip.squeeze(" ")
    self.normalized_name = self.class.normalize_card_name(name) if name.present?
  end
end
