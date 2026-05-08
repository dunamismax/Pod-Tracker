class GameNightForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  MAX_CHECK_INS = 8
  MAX_INVITATIONS = 12
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  attribute :name, :string
  attribute :played_on, :date
  attribute :location, :string
  attribute :notes, :string
  attribute :check_ins
  attribute :invitations
  attribute :invitation_message, :string

  attr_accessor :user

  validate :name_present
  validate :played_on_present
  validate :check_ins_valid
  validate :invitations_valid
  validate :at_least_one_attendee

  def check_in_rows
    rows = normalized_check_ins
    rows = [ {}, {}, {}, {} ] if rows.empty?
    rows.first(MAX_CHECK_INS)
  end

  def invitation_rows
    rows = normalized_invitations
    rows = [ {}, {}, {}, {} ] if rows.empty?
    rows.first(MAX_INVITATIONS)
  end

  def populated_check_ins
    normalized_check_ins.select do |row|
      row["player_name"].present? || row["deck_id"].present?
    end
  end

  def populated_invitations
    normalized_invitations.select do |row|
      row["email_address"].to_s.strip.present?
    end
  end

  private

  def name_present
    errors.add(:name, "is required") if name.to_s.strip.blank?
  end

  def played_on_present
    errors.add(:played_on, "is required") if played_on.blank?
  end

  def at_least_one_attendee
    return if populated_check_ins.any? || populated_invitations.any?

    errors.add(:base, "Add at least one in-person check-in or one invitation")
  end

  def check_ins_valid
    rows = populated_check_ins
    return if rows.empty?

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

  def invitations_valid
    rows = populated_invitations
    return if rows.empty?

    if rows.size > MAX_INVITATIONS
      errors.add(:invitations, "can include at most #{MAX_INVITATIONS} email invites")
    end

    seen = []
    host_email = user&.email_address.to_s.downcase
    rows.each_with_index do |row, index|
      row_label = "Invite row #{index + 1}"
      email = row["email_address"].to_s.strip.downcase

      if email.blank?
        errors.add(:invitations, "#{row_label} needs an email")
        next
      end

      unless email.match?(EMAIL_FORMAT)
        errors.add(:invitations, "#{row_label} email looks invalid")
        next
      end

      if email == host_email
        errors.add(:invitations, "#{row_label} can't invite the host")
        next
      end

      if seen.include?(email)
        errors.add(:invitations, "#{row_label} duplicates another invite")
        next
      end
      seen << email
    end
  end

  def normalized_check_ins
    coerce_to_rows(check_ins)
  end

  def normalized_invitations
    coerce_to_rows(invitations)
  end

  def coerce_to_rows(value)
    case value
    when ActionController::Parameters
      value.to_unsafe_h.values
    when Hash
      value.values
    when Array
      value
    else
      []
    end.map { |row| row.to_h.transform_keys(&:to_s) }
  end
end
