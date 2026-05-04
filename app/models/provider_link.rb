class ProviderLink < ApplicationRecord
  PROVIDERS = %w[archidekt moxfield paste text_export].freeze
  SYNC_STATUSES = %w[pending synced stale failed disabled].freeze

  belongs_to :deck

  validates :provider, inclusion: { in: PROVIDERS }
  validates :sync_status, inclusion: { in: SYNC_STATUSES }
  validates :url, presence: true
end
