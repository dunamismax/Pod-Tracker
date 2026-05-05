class GameNightForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  MAX_CHECK_INS = 8

  attribute :name, :string
  attribute :played_on, :date
  attribute :location, :string
  attribute :notes, :string
  attribute :check_ins

  attr_accessor :user

  validate :name_present
  validate :played_on_present
  validate :check_ins_valid

  def check_in_rows
    rows = normalized_check_ins
    rows = [ {}, {}, {}, {} ] if rows.empty?
    rows.first(MAX_CHECK_INS)
  end

  def populated_check_ins
    normalized_check_ins.select do |row|
      row["player_name"].present? || row["deck_id"].present?
    end
  end

  private

  def name_present
    errors.add(:name, "is required") if name.to_s.strip.blank?
  end

  def played_on_present
    errors.add(:played_on, "is required") if played_on.blank?
  end

  def check_ins_valid
    rows = populated_check_ins
    if rows.empty?
      errors.add(:check_ins, "must include at least one player and deck")
      return
    end

    if rows.size > MAX_CHECK_INS
      errors.add(:check_ins, "can include at most #{MAX_CHECK_INS} players")
    end

    player_names = []
    deck_ids = []
    rows.each_with_index do |row, index|
      row_number = index + 1
      player_name = row["player_name"].to_s.strip
      deck_id = row["deck_id"].to_s

      errors.add(:check_ins, "row #{row_number} needs a player name") if player_name.blank?
      errors.add(:check_ins, "row #{row_number} needs a deck") if deck_id.blank?

      player_names << Player.normalize_card_name(player_name) if player_name.present?
      deck_ids << deck_id if deck_id.present?
    end

    if player_names.uniq.size != player_names.size
      errors.add(:check_ins, "must use each player only once")
    end

    if user.present? && deck_ids.present?
      owned_ids = user.decks.where(id: deck_ids).pluck(:id).map(&:to_s)
      missing_ids = deck_ids - owned_ids
      errors.add(:check_ins, "include decks not owned by you") if missing_ids.any?
    end
  end

  def normalized_check_ins
    case check_ins
    when ActionController::Parameters
      check_ins.to_unsafe_h.values
    when Hash
      check_ins.values
    when Array
      check_ins
    else
      []
    end.map { |row| row.to_h.transform_keys(&:to_s) }
  end
end
