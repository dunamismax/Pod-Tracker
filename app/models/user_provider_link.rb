class UserProviderLink < ApplicationRecord
  PROVIDERS = %w[archidekt moxfield].freeze
  PROVIDER_LABELS = {
    "archidekt" => "Archidekt",
    "moxfield" => "Moxfield"
  }.freeze
  PROVIDER_HOSTS = {
    "archidekt" => %w[archidekt.com www.archidekt.com],
    "moxfield" => %w[moxfield.com www.moxfield.com]
  }.freeze

  belongs_to :user

  normalizes :handle, with: ->(value) { value.to_s.strip.presence }
  normalizes :profile_url, with: ->(value) { value.to_s.strip.presence }
  normalizes :label, with: ->(value) { value.to_s.strip.presence }

  before_validation :assign_normalized_handle

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :handle, presence: true, length: { maximum: 80 }
  validates :normalized_handle, presence: true, length: { maximum: 80 }
  validates :profile_url, presence: true, length: { maximum: 500 }
  validates :label, length: { maximum: 60 }, allow_nil: true
  validates :notes, length: { maximum: 1000 }, allow_nil: true
  validate :profile_url_must_be_http
  validate :profile_url_host_matches_provider
  validates :normalized_handle, uniqueness: { scope: [ :user_id, :provider ], case_sensitive: false }

  def provider_label
    PROVIDER_LABELS.fetch(provider, provider.to_s.humanize)
  end

  def export_payload
    {
      id: id,
      provider: provider,
      handle: handle,
      profile_url: profile_url,
      label: label,
      notes: notes,
      created_at: created_at&.utc&.iso8601,
      updated_at: updated_at&.utc&.iso8601
    }
  end

  private
    def assign_normalized_handle
      self.normalized_handle = handle.to_s.strip.downcase.presence
    end

    def profile_url_must_be_http
      return if profile_url.blank?
      uri = URI.parse(profile_url)
      return if uri.is_a?(URI::HTTP) && uri.host.present?
      errors.add(:profile_url, "must be an http(s) URL")
    rescue URI::InvalidURIError
      errors.add(:profile_url, "must be a valid URL")
    end

    def profile_url_host_matches_provider
      return if profile_url.blank? || provider.blank?
      hosts = PROVIDER_HOSTS[provider]
      return if hosts.blank?
      uri = URI.parse(profile_url)
      return if uri.host && hosts.include?(uri.host.downcase)
      errors.add(:profile_url, "must point at #{hosts.first}")
    rescue URI::InvalidURIError
      # handled by profile_url_must_be_http
    end
end
