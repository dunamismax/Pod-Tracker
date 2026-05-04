class DeckImportForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  MAX_DECKLIST_BYTES = 64.kilobytes

  attribute :name, :string
  attribute :decklist, :string
  attribute :commander_hint, :string

  validates :decklist, presence: { message: "is required" }
  validate :decklist_size_within_limit
  validate :decklist_has_content_lines

  def to_partial_path
    "decks/import_form"
  end

  private

  def decklist_size_within_limit
    return if decklist.blank?
    return if decklist.bytesize <= MAX_DECKLIST_BYTES

    errors.add(:decklist, "is too large (limit #{MAX_DECKLIST_BYTES / 1024} KB)")
  end

  def decklist_has_content_lines
    return if decklist.blank?

    content_lines = decklist.each_line.reject do |line|
      stripped = line.strip
      stripped.empty? || stripped.start_with?("//")
    end
    return if content_lines.any?

    errors.add(:decklist, "must contain at least one card line")
  end
end
