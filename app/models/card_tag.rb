class CardTag < ApplicationRecord
  CATEGORIES = %w[role salt social_friction].freeze
  SEVERITIES = %w[low moderate high].freeze
  SLUG_FORMAT = /\A[a-z0-9_]+\z/

  has_many :card_tag_assignments, dependent: :destroy
  has_many :oracle_cards, through: :card_tag_assignments

  validates :slug, presence: true, uniqueness: true,
    format: { with: SLUG_FORMAT, message: "must be lowercase letters, digits, or underscores" }
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :label, presence: true
  validates :default_severity, inclusion: { in: SEVERITIES }, allow_nil: true

  scope :role, -> { where(category: "role") }
  scope :salt, -> { where(category: "salt") }
  scope :social_friction, -> { where(category: "social_friction") }
  scope :ordered, -> { order(:category, :slug) }

  def role?
    category == "role"
  end

  def salt?
    category == "salt"
  end

  def social_friction?
    category == "social_friction"
  end
end
