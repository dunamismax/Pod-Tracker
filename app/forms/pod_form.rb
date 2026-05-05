class PodForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  GUEST_LABEL_MAX = 80

  attribute :name, :string
  attribute :deck_ids
  attribute :slot_labels
  attribute :guest_deck

  validate :name_present
  validate :deck_count_in_range
  validate :deck_ids_unique
  validate :decks_owned_by_user
  validate :guest_deck_inputs_valid

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

  def guest_deck_attrs
    case guest_deck
    when Hash
      guest_deck.transform_keys(&:to_s)
    when ActionController::Parameters
      guest_deck.to_unsafe_h.transform_keys(&:to_s)
    else
      {}
    end
  end

  def guest_deck_provided?
    attrs = guest_deck_attrs
    attrs["decklist"].to_s.strip.present? ||
      attrs["archidekt_url"].to_s.strip.present? ||
      attrs["moxfield_url"].to_s.strip.present?
  end

  def guest_decklist
    guest_deck_attrs["decklist"].to_s
  end

  def guest_archidekt_url
    guest_deck_attrs["archidekt_url"].to_s.strip
  end

  def guest_moxfield_url
    guest_deck_attrs["moxfield_url"].to_s.strip
  end

  def guest_name
    guest_deck_attrs["name"].to_s.strip
  end

  def guest_label
    guest_deck_attrs["label"].to_s.strip
  end

  def guest_source
    return :archidekt if guest_archidekt_url.present?
    return :moxfield if guest_moxfield_url.present?
    return :pasted if guest_decklist.strip.present?

    nil
  end

  def total_slot_count
    deck_id_array.size + (guest_deck_provided? ? 1 : 0)
  end

  private

  def name_present
    errors.add(:name, "is required") if name.to_s.strip.empty?
  end

  def deck_count_in_range
    count = total_slot_count
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

  def guest_deck_inputs_valid
    return unless guest_deck_provided?

    sources_supplied = [ guest_archidekt_url, guest_moxfield_url, guest_decklist.strip ].count(&:present?)
    if sources_supplied > 1
      errors.add(:guest_deck, "must use only one of paste, Archidekt URL, or Moxfield URL")
    end

    if guest_decklist.bytesize > DeckImportForm::MAX_DECKLIST_BYTES
      errors.add(:guest_deck, "decklist is too large (limit #{DeckImportForm::MAX_DECKLIST_BYTES / 1024} KB)")
    end

    if guest_label.length > GUEST_LABEL_MAX
      errors.add(:guest_deck, "label is too long")
    end
  end
end
