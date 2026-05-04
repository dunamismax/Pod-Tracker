class LegalitySnapshot < ApplicationRecord
  validates :source, :format, :effective_on, :fetched_at, presence: true

  before_validation :set_default_fetched_at

  private

  def set_default_fetched_at
    self.fetched_at ||= Time.current
  end
end
