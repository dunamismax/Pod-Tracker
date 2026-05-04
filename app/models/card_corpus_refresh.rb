class CardCorpusRefresh < ApplicationRecord
  SOURCES = %w[scryfall].freeze
  STATUSES = %w[pending running succeeded failed].freeze

  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :bulk_type, :source_uri, :fetched_at, presence: true
  validates :object_count, :card_set_count, :oracle_card_count, :card_printing_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :set_default_fetched_at

  def mark_running!
    update!(status: "running", started_at: Time.current)
  end

  def mark_succeeded!(counts)
    update!(
      status: "succeeded",
      completed_at: Time.current,
      object_count: counts.fetch(:objects),
      card_set_count: counts.fetch(:card_sets),
      oracle_card_count: counts.fetch(:oracle_cards),
      card_printing_count: counts.fetch(:card_printings),
      error_code: nil,
      error_message: nil
    )
  end

  def mark_failed!(error)
    update!(
      status: "failed",
      failed_at: Time.current,
      error_code: error.class.name,
      error_message: error.message
    )
  end

  private

  def set_default_fetched_at
    self.fetched_at ||= Time.current
  end
end
