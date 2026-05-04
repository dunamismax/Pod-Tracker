class DeckImportForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  MAX_DECKLIST_BYTES = 64.kilobytes

  attribute :name, :string
  attribute :decklist, :string
  attribute :commander_hint, :string
  attribute :decklist_file

  validate :decklist_or_file_present
  validate :decklist_size_within_limit
  validate :decklist_has_content_lines
  validate :uploaded_file_size_within_limit

  def to_partial_path
    "decks/import_form"
  end

  def upload_provided?
    file = decklist_file
    return false if file.blank?
    return file.size.to_i.positive? if file.respond_to?(:size)

    true
  end

  def pasted_text_provided?
    decklist.present?
  end

  private

  def decklist_or_file_present
    return if pasted_text_provided? || upload_provided?

    errors.add(:decklist, "is required")
  end

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

  def uploaded_file_size_within_limit
    return unless upload_provided?
    return unless decklist_file.respond_to?(:size)
    return if decklist_file.size.to_i <= MAX_DECKLIST_BYTES

    errors.add(:decklist_file, "is too large (limit #{MAX_DECKLIST_BYTES / 1024} KB)")
  end
end
