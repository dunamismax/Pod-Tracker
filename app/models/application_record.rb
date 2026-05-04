class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.normalize_card_name(value)
    I18n.transliterate(value.to_s)
      .downcase
      .gsub(/[^a-z0-9]+/, " ")
      .squeeze(" ")
      .strip
  end
end
