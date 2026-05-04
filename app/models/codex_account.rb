class CodexAccount < ApplicationRecord
  AUTH_MODES = %w[chatgpt_browser chatgpt_device_code].freeze
  STATUSES = %w[pending connected disconnected expired failed].freeze

  belongs_to :user

  encrypts :encrypted_credential_payload

  validates :auth_mode, presence: true, inclusion: { in: AUTH_MODES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :displayed_email, length: { maximum: 254 }, allow_nil: true
  validates :plan_type, length: { maximum: 60 }, allow_nil: true
  validates :user_id, uniqueness: true

  scope :connected, -> { where(status: "connected") }

  def connected?
    status == "connected"
  end

  def disconnected?
    status == "disconnected"
  end

  def credential_present?
    encrypted_credential_payload.present?
  end

  def disconnect!(now: Time.current)
    update!(
      status: "disconnected",
      encrypted_credential_payload: nil,
      credential_metadata: {},
      rate_limit_snapshot: {},
      credentials_expire_at: nil,
      disconnected_at: now,
      last_error_code: nil,
      last_error_message: nil
    )
  end

  def export_payload
    {
      auth_mode: auth_mode,
      status: status,
      displayed_email: displayed_email,
      plan_type: plan_type,
      rate_limit_snapshot: rate_limit_snapshot,
      credential_metadata_keys: credential_metadata.is_a?(Hash) ? credential_metadata.keys.sort : [],
      credential_present: credential_present?,
      connected_at: iso(connected_at),
      disconnected_at: iso(disconnected_at),
      last_synced_at: iso(last_synced_at),
      last_failed_at: iso(last_failed_at),
      credentials_expire_at: iso(credentials_expire_at),
      last_error_code: last_error_code,
      created_at: iso(created_at),
      updated_at: iso(updated_at)
    }
  end

  private
    def iso(value)
      value&.utc&.iso8601
    end
end
