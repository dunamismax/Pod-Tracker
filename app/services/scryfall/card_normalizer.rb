module Scryfall
  class CardNormalizer
    CARD_COLOR_ORDER = %w[W U B R G].freeze
    PRODUCED_MANA_ORDER = %w[W U B R G C].freeze
    IMAGE_URI_KEYS = %w[small normal large png art_crop border_crop].freeze
    LEGALITY_FORMAT_ORDER = %w[
      standard future historic timeless gladiator pioneer explorer modern legacy pauper vintage penny
      commander oathbreaker standardbrawl brawl alchemy paupercommander duel oldschool premodern predh
    ].freeze

    def initialize(card)
      @card = card
    end

    def card_set_attributes
      {
        scryfall_id: @card["set_id"],
        name: @card["set_name"] || @card.fetch("set").upcase,
        set_type: @card["set_type"],
        released_on: parse_date(@card["released_at"]),
        digital: @card["digital"] || false,
        raw_payload: @card.slice(
          "set_id",
          "set",
          "set_name",
          "set_type",
          "released_at",
          "digital",
          "scryfall_set_uri"
        )
      }
    end

    def oracle_attributes
      {
        name: @card.fetch("name"),
        layout: clean_string(@card["layout"]),
        mana_cost: clean_string(@card["mana_cost"]),
        mana_value: @card["cmc"],
        type_line: clean_string(@card["type_line"]),
        oracle_text: clean_string(@card["oracle_text"]),
        colors: ordered_strings(@card["colors"], CARD_COLOR_ORDER),
        color_identity: ordered_strings(@card["color_identity"], CARD_COLOR_ORDER),
        produced_mana: ordered_strings(@card["produced_mana"], PRODUCED_MANA_ORDER),
        keywords: clean_strings(@card["keywords"]).sort,
        legalities: legalities,
        faces: faces,
        raw_payload: @card,
        reserved: @card["reserved"] || false,
        edhrec_rank: @card["edhrec_rank"]
      }
    end

    def printing_attributes(card_set:, oracle_card:)
      {
        oracle_card: oracle_card,
        card_set: card_set,
        lang: clean_string(@card["lang"]) || "en",
        name: @card.fetch("name"),
        collector_number: @card.fetch("collector_number"),
        rarity: clean_string(@card["rarity"]),
        released_on: parse_date(@card["released_at"]),
        image_status: clean_string(@card["image_status"]),
        image_uris: printing_image_uris,
        prices: @card["prices"] || {},
        purchase_uris: @card["purchase_uris"] || {},
        raw_payload: @card
      }
    end

    def faces
      Array(@card["card_faces"]).filter_map do |face|
        normalized_face(face) if face.is_a?(Hash)
      end
    end

    def printing_image_uris
      top_level_image_uris = image_uris(@card["image_uris"])
      return top_level_image_uris if top_level_image_uris.present?

      face_image_uris = faces.filter_map do |face|
        next if face.fetch("image_uris").blank?

        face.slice("name", "normalized_name", "image_uris")
      end

      face_image_uris.present? ? { "faces" => face_image_uris } : {}
    end

    private

    def normalized_face(face)
      {
        "name" => face.fetch("name"),
        "normalized_name" => ApplicationRecord.normalize_card_name(face.fetch("name")),
        "mana_cost" => clean_string(face["mana_cost"]),
        "type_line" => clean_string(face["type_line"]),
        "oracle_text" => clean_string(face["oracle_text"]),
        "colors" => ordered_strings(face["colors"], CARD_COLOR_ORDER),
        "color_indicator" => ordered_strings(face["color_indicator"], CARD_COLOR_ORDER),
        "power" => clean_string(face["power"]),
        "toughness" => clean_string(face["toughness"]),
        "loyalty" => clean_string(face["loyalty"]),
        "defense" => clean_string(face["defense"]),
        "flavor_text" => clean_string(face["flavor_text"]),
        "image_uris" => image_uris(face["image_uris"])
      }.compact
    end

    def legalities
      raw_legalities = (@card["legalities"] || {}).to_h.transform_keys(&:to_s).transform_values do |value|
        clean_string(value)&.downcase
      end

      sorted_keys(raw_legalities.keys, LEGALITY_FORMAT_ORDER).to_h do |format|
        [ format, raw_legalities.fetch(format) ]
      end
    end

    def image_uris(raw_image_uris)
      raw_image_uris = raw_image_uris.to_h.transform_keys(&:to_s)

      sorted_keys(raw_image_uris.keys, IMAGE_URI_KEYS).to_h do |key|
        [ key, clean_string(raw_image_uris.fetch(key)) ]
      end.compact
    end

    def ordered_strings(values, preferred_order)
      sorted_keys(clean_strings(values), preferred_order)
    end

    def clean_strings(values)
      Array(values).filter_map { |value| clean_string(value) }.uniq
    end

    def sorted_keys(keys, preferred_order)
      keys.sort_by { |key| [ preferred_order.index(key) || preferred_order.length, key ] }
    end

    def clean_string(value)
      value.to_s.strip.presence unless value.nil?
    end

    def parse_date(value)
      Date.iso8601(value) if value.present?
    end
  end
end
