class GameNightDeck < ApplicationRecord
  belongs_to :game_night
  belongs_to :player
  belongs_to :deck

  validates :deck_name_snapshot, presence: true
  validates :position,
    numericality: { only_integer: true, greater_than_or_equal_to: 1 },
    uniqueness: { scope: :game_night_id }
  validates :player_id, uniqueness: { scope: :game_night_id }

  before_validation :snapshot_deck

  private

  def snapshot_deck
    return unless deck

    self.deck_name_snapshot = deck.name
    self.commander_names_snapshot = deck.commander_names
  end
end
