class LegalitySnapshot < ApplicationRecord
  SOURCES = %w[mtgcommander].freeze
  FORMATS = %w[commander].freeze

  validates :source, :format, :effective_on, :fetched_at, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :format, inclusion: { in: FORMATS }

  before_validation :normalize_snapshot_arrays
  before_validation :set_default_fetched_at

  scope :commander, -> { where(format: "commander") }
  scope :latest_first, -> { order(effective_on: :desc, fetched_at: :desc, id: :desc) }

  def self.current_commander
    commander.latest_first.first
  end

  def banned_card?(card_name)
    banned_normalized_names.include?(self.class.normalize_card_name(card_name))
  end

  def restricted_card?(card_name)
    restricted_normalized_names.include?(self.class.normalize_card_name(card_name))
  end

  def category_ban_labels
    category_bans.filter_map { |category| category["label"].presence }
  end

  private

  def set_default_fetched_at
    self.fetched_at ||= Time.current
  end

  def normalize_snapshot_arrays
    self.banned_names = normalize_names(banned_names)
    self.restricted_names = normalize_names(restricted_names)
    self.banned_normalized_names = normalized_names_for(banned_names)
    self.restricted_normalized_names = normalized_names_for(restricted_names)
  end

  def normalize_names(names)
    Array(names).compact_blank.map(&:to_s).map(&:strip).uniq
  end

  def normalized_names_for(names)
    normalize_names(names).map { |name| self.class.normalize_card_name(name) }.uniq
  end
end
