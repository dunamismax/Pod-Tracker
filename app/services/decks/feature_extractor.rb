module Decks
  class FeatureExtractor
    ROLE_TAG_SLUGS = %w[
      ramp fast_mana tutor card_draw protection removal stack_interaction
      board_wipe stax combo graveyard_use land win_condition
    ].freeze

    SALT_TAG_SLUGS = %w[
      salt_driver_fast_mana salt_driver_mass_land_denial salt_driver_extra_turns
      salt_driver_chaos salt_driver_theft salt_driver_repetitive_loop
      salt_driver_stax_lock salt_driver_compact_combo
    ].freeze

    FRICTION_TAG_SLUGS = %w[
      social_friction_combo_opacity social_friction_long_game
      social_friction_disclosure_required social_friction_interaction_asymmetry
    ].freeze

    MANA_CURVE_BUCKETS = [ 0, 1, 2, 3, 4, 5, 6 ].freeze

    Result = Struct.new(
      :total_cards, :nonland_count, :land_count, :mana_source_count,
      :role_counts, :salt_counts, :friction_counts,
      :mana_curve, :color_pip_counts, :commander_color_identity,
      :evidence_by_tag, :missing_oracle_count,
      keyword_init: true
    ) do
      def to_h
        {
          "total_cards" => total_cards,
          "nonland_count" => nonland_count,
          "land_count" => land_count,
          "mana_source_count" => mana_source_count,
          "role_counts" => role_counts,
          "salt_counts" => salt_counts,
          "friction_counts" => friction_counts,
          "mana_curve" => mana_curve,
          "color_pip_counts" => color_pip_counts,
          "commander_color_identity" => commander_color_identity,
          "missing_oracle_count" => missing_oracle_count,
          "evidence_by_tag" => evidence_by_tag
        }
      end
    end

    def call(deck)
      mainboard = deck.deck_cards.select { |dc| %w[main commander].include?(dc.board) }
      total_cards = mainboard.sum(&:quantity)

      normalized_names = mainboard.map(&:normalized_name).uniq.compact_blank
      tag_index = build_tag_index(normalized_names)
      oracle_index = build_oracle_index(normalized_names, deck)

      land_count = 0
      missing_oracle = 0
      mana_curve = MANA_CURVE_BUCKETS.each_with_object({}) { |b, h| h[b.to_s] = 0 }
      color_pip_counts = { "W" => 0, "U" => 0, "B" => 0, "R" => 0, "G" => 0, "C" => 0 }

      mainboard.each do |dc|
        oracle = oracle_index[dc.normalized_name]
        is_basic_land = CommanderFormat::LegalityChecker::BASIC_LAND_NORMALIZED_NAMES.include?(dc.normalized_name.to_s)

        if oracle.nil? && !is_basic_land
          missing_oracle += dc.quantity
        end

        if oracle_is_land?(oracle, dc)
          land_count += dc.quantity
        else
          add_to_curve(mana_curve, oracle, dc.quantity)
          add_to_color_pips(color_pip_counts, oracle, dc.quantity)
        end
      end

      role_counts = ROLE_TAG_SLUGS.index_with { |_| 0 }
      salt_counts = SALT_TAG_SLUGS.index_with { |_| 0 }
      friction_counts = FRICTION_TAG_SLUGS.index_with { |_| 0 }
      evidence_by_tag = Hash.new { |h, k| h[k] = [] }

      mainboard.each do |dc|
        slugs = tag_index[dc.normalized_name] || []
        slugs.each do |slug|
          if role_counts.key?(slug)
            role_counts[slug] += dc.quantity
            evidence_by_tag[slug] << dc.name
          elsif salt_counts.key?(slug)
            salt_counts[slug] += dc.quantity
            evidence_by_tag[slug] << dc.name
          elsif friction_counts.key?(slug)
            friction_counts[slug] += dc.quantity
            evidence_by_tag[slug] << dc.name
          end
        end
      end

      evidence_by_tag.transform_values! { |names| names.uniq.first(8) }

      role_counts["land"] = land_count if role_counts["land"].zero?
      mana_source_count = land_count + role_counts.fetch("ramp", 0) + role_counts.fetch("fast_mana", 0)
      nonland_count = [ total_cards - land_count, 0 ].max

      Result.new(
        total_cards: total_cards,
        nonland_count: nonland_count,
        land_count: land_count,
        mana_source_count: mana_source_count,
        role_counts: role_counts,
        salt_counts: salt_counts,
        friction_counts: friction_counts,
        mana_curve: mana_curve,
        color_pip_counts: color_pip_counts,
        commander_color_identity: commander_color_identity(deck, oracle_index),
        evidence_by_tag: evidence_by_tag.to_h,
        missing_oracle_count: missing_oracle
      )
    end

    private

    def build_tag_index(normalized_names)
      return {} if normalized_names.empty?

      rows = CardTagAssignment
               .joins(:card_tag)
               .where(normalized_card_name: normalized_names)
               .pluck(:normalized_card_name, "card_tags.slug")

      rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(name, slug), idx|
        idx[name] << slug
      end
    end

    def build_oracle_index(normalized_names, deck)
      preloaded = deck.deck_cards.includes(:oracle_card).each_with_object({}) do |dc, h|
        h[dc.normalized_name] = dc.oracle_card if dc.oracle_card
      end
      missing = normalized_names - preloaded.keys
      OracleCard.where(normalized_name: missing).each { |o| preloaded[o.normalized_name] = o } if missing.any?
      preloaded
    end

    def oracle_is_land?(oracle, deck_card)
      type_line = oracle&.type_line.to_s.downcase
      return true if type_line.include?("land")

      name = deck_card.normalized_name.to_s
      CommanderFormat::LegalityChecker::BASIC_LAND_NORMALIZED_NAMES.include?(name)
    end

    def add_to_curve(curve, oracle, quantity)
      return unless oracle&.mana_value

      bucket = oracle.mana_value.to_i
      key = bucket >= 6 ? "6" : bucket.to_s
      curve[key] = (curve[key] || 0) + quantity
    end

    def add_to_color_pips(pips, oracle, quantity)
      return unless oracle

      cost = oracle.mana_cost.to_s
      return if cost.empty?

      symbols = cost.scan(/\{([^}]+)\}/).flatten
      symbols.each do |symbol|
        if symbol.match?(/\A[WUBRG]\z/)
          pips[symbol] += quantity
        elsif symbol.include?("/")
          parts = symbol.split("/").select { |p| p.match?(/\A[WUBRG]\z/) }
          parts.each { |p| pips[p] += quantity }
        end
      end
    end

    def commander_color_identity(deck, oracle_index)
      identity = deck.commanders.flat_map do |cmdr|
        oracle = cmdr.oracle_card || oracle_index[cmdr.normalized_name] ||
                 OracleCard.find_by(normalized_name: cmdr.normalized_name)
        Array(oracle&.color_identity)
      end
      identity.compact.uniq.sort.presence || Array(deck.color_identity)
    end
  end
end
