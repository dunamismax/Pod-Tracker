class CollectionImportForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  MAX_COLLECTION_BYTES = 128.kilobytes

  attribute :collection_list, :string
  attribute :collection_file

  validate :collection_source_present
  validate :collection_list_size_within_limit
  validate :collection_list_has_content_lines
  validate :collection_file_size_within_limit

  def upload_provided?
    file = collection_file
    return false if file.blank?
    return file.size.to_i.positive? if file.respond_to?(:size)

    true
  end

  def pasted_text_provided?
    collection_list.present?
  end

  private

    def collection_source_present
      return if pasted_text_provided? || upload_provided?

      errors.add(:collection_list, "is required")
    end

    def collection_list_size_within_limit
      return if collection_list.blank?
      return if collection_list.bytesize <= MAX_COLLECTION_BYTES

      errors.add(:collection_list, "is too large (limit #{MAX_COLLECTION_BYTES / 1024} KB)")
    end

    def collection_list_has_content_lines
      return if collection_list.blank?

      content_lines = collection_list.each_line.reject do |line|
        stripped = line.strip
        stripped.empty? || stripped.start_with?("//", "#")
      end
      return if content_lines.any?

      errors.add(:collection_list, "must contain at least one card line")
    end

    def collection_file_size_within_limit
      return unless upload_provided?
      return unless collection_file.respond_to?(:size)
      return if collection_file.size.to_i <= MAX_COLLECTION_BYTES

      errors.add(:collection_file, "is too large (limit #{MAX_COLLECTION_BYTES / 1024} KB)")
    end
end
