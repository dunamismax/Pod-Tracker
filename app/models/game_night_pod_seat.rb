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

  private

  def snapshot_deck
    return unless deck

    self.deck_name_snapshot = deck.name
    self.commander_names_snapshot = deck.commander_names
  end
end
