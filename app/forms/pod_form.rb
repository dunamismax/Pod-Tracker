class PodForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :deck_ids
  attribute :slot_labels

  validate :name_present
  validate :deck_count_in_range
  validate :deck_ids_unique
  validate :decks_owned_by_user

  attr_accessor :user

  def deck_id_array
    Array(deck_ids).map(&:to_s).reject(&:blank?)
  end

  def slot_label_for(deck_id)
    case slot_labels
    when Hash, ActionController::Parameters
      slot_labels[deck_id.to_s].to_s
    else
      ""
    end
  end

  private

  def name_present
    errors.add(:name, "is required") if name.to_s.strip.empty?
  end

  def deck_count_in_range
    count = deck_id_array.size
    if count < Pod::MIN_SLOTS
      errors.add(:deck_ids, "must include at least #{Pod::MIN_SLOTS} decks")
    elsif count > Pod::MAX_SLOTS
      errors.add(:deck_ids, "can include at most #{Pod::MAX_SLOTS} decks")
    end
  end

  def deck_ids_unique
    ids = deck_id_array
    return if ids.empty?
    return if ids.uniq.size == ids.size

    errors.add(:deck_ids, "must reference distinct decks")
  end

  def decks_owned_by_user
    return if user.blank?
    ids = deck_id_array
    return if ids.empty?

    owned = user.decks.where(id: ids).pluck(:id).map(&:to_s)
    missing = ids - owned
    return if missing.empty?

    errors.add(:deck_ids, "include decks not owned by you")
  end
end
