class OracleCard < ApplicationRecord
  has_many :card_printings, dependent: :destroy
  has_many :deck_cards, dependent: :nullify
  has_many :commanders, dependent: :nullify
  has_many :rulings, dependent: :destroy
  has_many :salt_social_friction_evidences, dependent: :nullify
  has_many :card_tag_assignments, dependent: :nullify
  has_many :card_tags, through: :card_tag_assignments

  validates :scryfall_oracle_id, :name, :normalized_name, presence: true

  before_validation :set_normalized_name
  after_save_commit :backfill_card_tag_assignments

  def card_tag_slugs(category: nil)
    scope = card_tags
    scope = scope.where(category: category) if category
    scope.distinct.pluck(:slug)
  end

  private

  def set_normalized_name
    self.normalized_name = self.class.normalize_card_name(name) if name.present?
  end

  def backfill_card_tag_assignments
    return unless previously_new_record? || saved_change_to_normalized_name?

    CardTagAssignment.where(normalized_card_name: normalized_name, oracle_card_id: nil)
                     .update_all(oracle_card_id: id, updated_at: Time.current)
  end
end
