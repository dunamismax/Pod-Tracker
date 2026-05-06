class MatchupNote < ApplicationRecord
  belongs_to :user
  belongs_to :deck
  belongs_to :commander, optional: true
  belongs_to :opponent, class_name: "Player", optional: true, inverse_of: :matchup_notes_as_opponent
  belongs_to :pod, optional: true
  belongs_to :game_night, optional: true

  validates :body, :happened_at, presence: true
  validates :game_night_pod_number,
    numericality: { only_integer: true, greater_than_or_equal_to: 1 },
    allow_nil: true
  validate :associations_belong_to_user
  validate :commander_belongs_to_deck
  validate :pod_number_requires_session

  before_validation :normalize_tags

  scope :recent, -> { order(happened_at: :desc, id: :desc) }

  def tag_list
    tags.join(", ")
  end

  def tag_list=(value)
    self.tags = self.class.parse_tags(value)
  end

  def self.parse_tags(value)
    Array(value).flat_map { |entry| entry.to_s.split(/[,\n#]/) }
                .map { |tag| normalize_card_name(tag) }
                .reject(&:blank?)
                .uniq
  end

  private

  def normalize_tags
    self.tags = self.class.parse_tags(tags)
  end

  def associations_belong_to_user
    return unless user

    {
      deck: deck,
      opponent: opponent,
      pod: pod,
      game_night: game_night
    }.each do |name, record|
      next if record.blank?
      next if record.user_id == user_id

      errors.add(name, "does not belong to this account")
    end
  end

  def commander_belongs_to_deck
    return if commander.blank? || deck.blank?
    return if commander.deck_id == deck_id

    errors.add(:commander, "must belong to the selected deck")
  end

  def pod_number_requires_session
    return if game_night_pod_number.blank? || game_night.present?

    errors.add(:game_night_pod_number, "requires a session")
  end
end
