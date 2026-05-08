class GameNightInvitation < ApplicationRecord
  STATUSES = %w[pending accepted declined cancelled].freeze
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  belongs_to :game_night
  belongs_to :invited_user, class_name: "User", optional: true
  belongs_to :responded_user, class_name: "User", optional: true
  belongs_to :player, optional: true
  belongs_to :deck, optional: true

  before_validation :normalize_email
  before_validation :assign_token, on: :create
  before_validation :stamp_invited_at, on: :create
  before_validation :resolve_invited_user

  validates :email_address, presence: true, format: { with: EMAIL_FORMAT }, length: { maximum: 254 }
  validates :status, inclusion: { in: STATUSES }
  validates :position,
    numericality: { only_integer: true, greater_than_or_equal_to: 1 },
    uniqueness: { scope: :game_night_id }
  validates :email_address, uniqueness: { scope: :game_night_id, case_sensitive: false }
  validates :token, presence: true, uniqueness: true

  STATUSES.each do |state|
    define_method("#{state}?") { status == state }
  end

  def open?
    pending?
  end

  def display_label
    return display_name if display_name.present?
    invited_user&.attribution_name || email_address
  end

  def matches_user?(user)
    return false unless user

    user_email = user.email_address.to_s.downcase
    user_email.present? && user_email == email_address.to_s.downcase
  end

  private

  def normalize_email
    self.email_address = email_address.to_s.strip.downcase.presence
  end

  def assign_token
    return if token.present?

    self.token = self.class.generate_unique_token
  end

  def stamp_invited_at
    self.invited_at ||= Time.current
  end

  def resolve_invited_user
    return if invited_user_id.present?
    return if email_address.blank?

    self.invited_user = User.find_by("LOWER(email_address) = ?", email_address.to_s.downcase)
  end

  def self.generate_unique_token
    loop do
      candidate = SecureRandom.urlsafe_base64(16)
      break candidate unless exists?(token: candidate)
    end
  end
end
