class GameNight < ApplicationRecord
  STATUSES = %w[draft seated completed archived].freeze

  belongs_to :user
  has_many :game_night_players, -> { order(:position) }, dependent: :destroy
  has_many :players, through: :game_night_players
  has_many :game_night_decks, -> { order(:position) }, dependent: :destroy
  has_many :game_night_pod_seats, -> { order(:pod_number, :seat_number) }, dependent: :destroy
  has_many :game_night_pod_results, -> { order(:pod_number) }, dependent: :destroy
  has_many :decks, through: :game_night_decks
  has_many :audit_events, as: :auditable, dependent: :nullify

  validates :name, :played_on, presence: true
  validates :status, inclusion: { in: STATUSES }

  def checked_in_count
    game_night_players.size
  end
end
