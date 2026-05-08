class User < ApplicationRecord
  PREFERRED_UNITS = %w[imperial metric].freeze
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :game_nights, dependent: :destroy
  has_many :pods, dependent: :destroy
  has_many :decks, dependent: :destroy
  has_many :players, dependent: :destroy
  has_many :analysis_runs, dependent: :nullify
  has_many :game_night_invitations,
           foreign_key: :invited_user_id,
           inverse_of: :invited_user,
           dependent: :nullify
  has_many :responded_game_night_invitations,
           class_name: "GameNightInvitation",
           foreign_key: :responded_user_id,
           inverse_of: :responded_user,
           dependent: :nullify
  has_many :matchup_notes, dependent: :destroy
  has_many :collection_cards, dependent: :destroy
  has_many :collection_imports, dependent: :destroy
  has_many :unresolved_entries, dependent: :destroy
  has_many :audit_events, dependent: :nullify
  has_one :codex_account, dependent: :destroy
  has_many :codex_login_attempts, dependent: :destroy
  has_many :provider_links, class_name: "UserProviderLink", dependent: :destroy

  generates_token_for :email_verification, expires_in: 1.day do
    email_address
  end

  normalizes :email_address, with: ->(e) { e.to_s.strip.downcase }
  normalizes :display_name, with: ->(name) { name.to_s.strip.presence }

  validates :email_address, presence: true, format: { with: EMAIL_FORMAT }, length: { maximum: 254 }, uniqueness: { case_sensitive: false }
  validates :display_name, length: { maximum: 60 }, allow_nil: true
  validates :preferred_units, presence: true, inclusion: { in: PREFERRED_UNITS }
  validate :timezone_is_known

  def email_verified?
    email_verified_at.present?
  end

  def attribution_name
    display_name.presence || email_address
  end

  private
    def timezone_is_known
      return if timezone.present? && ActiveSupport::TimeZone[timezone].present?
      errors.add(:timezone, "is not included in the list")
    end
end
