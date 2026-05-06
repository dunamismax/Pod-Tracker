class CollectionImport < ApplicationRecord
  SOURCE_TYPES = %w[pasted_text uploaded_text csv].freeze
  STATUSES = %w[pending completed completed_with_unresolved failed].freeze

  belongs_to :user
  has_many :unresolved_entries, dependent: :destroy

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :imported_count, :unresolved_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def completed?
    status.in?(%w[completed completed_with_unresolved])
  end
end
