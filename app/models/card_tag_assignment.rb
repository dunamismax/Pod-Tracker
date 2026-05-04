class CardTagAssignment < ApplicationRecord
  SOURCES = %w[curated inferred admin].freeze

  belongs_to :card_tag
  belongs_to :oracle_card, optional: true

  validates :card_name, :normalized_card_name, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :severity, inclusion: { in: CardTag::SEVERITIES }, allow_nil: true
  validates :card_tag_id, uniqueness: { scope: :normalized_card_name }

  before_validation :set_normalized_card_name
  before_validation :link_oracle_card

  scope :for_card_name, ->(name) {
    where(normalized_card_name: ApplicationRecord.normalize_card_name(name))
  }
  scope :role, -> { joins(:card_tag).merge(CardTag.role) }
  scope :salt, -> { joins(:card_tag).merge(CardTag.salt) }
  scope :social_friction, -> { joins(:card_tag).merge(CardTag.social_friction) }

  def effective_weight
    return weight if weight.present?

    case card_tag&.category
    when "salt"            then card_tag.salt_weight
    when "social_friction" then card_tag.friction_weight
    end
  end

  def effective_severity
    severity.presence || card_tag&.default_severity
  end

  private

  def set_normalized_card_name
    self.normalized_card_name = self.class.normalize_card_name(card_name) if card_name.present?
  end

  def link_oracle_card
    return if oracle_card_id.present?
    return if normalized_card_name.blank?

    self.oracle_card = OracleCard.find_by(normalized_name: normalized_card_name)
  end
end
