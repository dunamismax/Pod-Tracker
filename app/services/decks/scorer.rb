module Decks
  class Scorer
    RUBRIC_VERSION = "deterministic-v0".freeze

    SEVERITY_WEIGHTS = { "high" => 2.0, "moderate" => 1.0, "low" => 0.5 }.freeze

    Score = Struct.new(:value, :evidence, keyword_init: true) do
      def to_h
        { "value" => value, "evidence" => evidence }
      end
    end

    Result = Struct.new(
      :scores, :recommendations, :rubric_version, keyword_init: true
    ) do
      def to_h
        {
          "rubric_version" => rubric_version,
          "scores" => scores.transform_values(&:to_h),
          "recommendations" => recommendations
        }
      end
    end

    def initialize(severity_lookup: nil)
      @severity_lookup = severity_lookup
    end

    def call(features)
      f = features
      power = score_power(f)
      speed = score_speed(f)
      interaction = score_interaction(f)
      consistency = score_consistency(f)
      salt = score_salt(f)
      friction = score_friction(f)

      Result.new(
        rubric_version: RUBRIC_VERSION,
        scores: {
          "power" => power,
          "speed" => speed,
          "interaction" => interaction,
          "consistency" => consistency,
          "salt" => salt,
          "social_friction" => friction
        },
        recommendations: build_recommendations(f)
      )
    end

    private

    def score_power(f)
      fast_mana = f.role_counts.fetch("fast_mana", 0)
      tutors = f.role_counts.fetch("tutor", 0)
      combo = f.role_counts.fetch("combo", 0)
      card_draw = f.role_counts.fetch("card_draw", 0)

      raw = 3
      raw += band(fast_mana, [ [ 1, 1 ], [ 3, 2 ], [ 5, 3 ] ])
      raw += band(tutors, [ [ 1, 1 ], [ 3, 2 ], [ 6, 3 ] ])
      raw += band(combo, [ [ 1, 1 ], [ 4, 2 ] ])
      raw += band(card_draw, [ [ 5, 1 ], [ 9, 2 ] ])

      Score.new(value: clamp10(raw), evidence: power_evidence(f, fast_mana, tutors, combo, card_draw))
    end

    def score_speed(f)
      fast_mana = f.role_counts.fetch("fast_mana", 0)
      mana_sources = f.mana_source_count
      low_curve = (f.mana_curve["0"] || 0) + (f.mana_curve["1"] || 0) + (f.mana_curve["2"] || 0)

      raw = 3
      raw += band(mana_sources, [ [ 34, 0 ], [ 38, 1 ], [ 43, 2 ] ])
      raw += band(fast_mana, [ [ 1, 1 ], [ 3, 2 ], [ 5, 3 ] ])
      raw += band(low_curve, [ [ 12, 1 ], [ 18, 2 ] ])
      raw -= 1 if mana_sources < 34

      Score.new(value: clamp10(raw), evidence: speed_evidence(f, fast_mana, mana_sources, low_curve))
    end

    def score_interaction(f)
      removal = f.role_counts.fetch("removal", 0)
      counters = f.role_counts.fetch("stack_interaction", 0)
      wipes = f.role_counts.fetch("board_wipe", 0)
      protection = f.role_counts.fetch("protection", 0)

      raw = 3
      raw += band(removal, [ [ 4, 1 ], [ 7, 2 ], [ 11, 3 ] ])
      raw += band(counters, [ [ 1, 1 ], [ 4, 2 ], [ 8, 3 ] ])
      raw += band(wipes, [ [ 1, 1 ], [ 3, 2 ] ])
      raw += band(protection, [ [ 1, 1 ], [ 3, 2 ] ])

      Score.new(value: clamp10(raw), evidence: interaction_evidence(f, removal, counters, wipes, protection))
    end

    def score_consistency(f)
      card_draw = f.role_counts.fetch("card_draw", 0)
      tutors = f.role_counts.fetch("tutor", 0)
      lands = f.land_count
      mana_sources = f.mana_source_count

      raw = 3
      raw += band(card_draw, [ [ 5, 1 ], [ 8, 2 ], [ 13, 3 ] ])
      raw += band(tutors, [ [ 2, 1 ], [ 4, 2 ] ])
      raw += band(mana_sources, [ [ 38, 1 ], [ 43, 2 ] ])
      raw -= 1 if lands < 34
      raw -= 1 if f.missing_oracle_count > (f.total_cards / 4)

      Score.new(value: clamp10(raw), evidence: consistency_evidence(f, card_draw, tutors, lands, mana_sources))
    end

    def score_salt(f)
      raw = 0.0
      drivers = []
      f.salt_counts.each do |slug, count|
        next if count.zero?

        weight = severity_weight_for(slug)
        contribution = count * weight
        raw += contribution
        drivers << {
          "tag" => slug,
          "label" => slug_to_label(slug),
          "count" => count,
          "weight" => weight,
          "cards" => f.evidence_by_tag[slug] || []
        }
      end

      value = saltlike_to_ten(raw)
      Score.new(value: value, evidence: { "drivers" => drivers, "raw_weight" => raw.round(2) })
    end

    def score_friction(f)
      raw = 0.0
      drivers = []
      f.friction_counts.each do |slug, count|
        next if count.zero?

        contribution = count * 1.0
        raw += contribution
        drivers << {
          "tag" => slug,
          "label" => slug_to_label(slug),
          "count" => count,
          "cards" => f.evidence_by_tag[slug] || []
        }
      end

      raw += 0.5 * f.role_counts.fetch("combo", 0)
      raw += 0.5 * f.role_counts.fetch("stax", 0)

      value = saltlike_to_ten(raw)
      Score.new(value: value, evidence: { "drivers" => drivers, "raw_weight" => raw.round(2) })
    end

    def power_evidence(f, fast_mana, tutors, combo, card_draw)
      {
        "fast_mana" => { "count" => fast_mana, "cards" => f.evidence_by_tag["fast_mana"] || [] },
        "tutors" => { "count" => tutors, "cards" => f.evidence_by_tag["tutor"] || [] },
        "combo_pieces" => { "count" => combo, "cards" => f.evidence_by_tag["combo"] || [] },
        "card_draw" => { "count" => card_draw, "cards" => f.evidence_by_tag["card_draw"] || [] }
      }
    end

    def speed_evidence(f, fast_mana, mana_sources, low_curve)
      {
        "mana_sources" => mana_sources,
        "lands" => f.land_count,
        "fast_mana" => { "count" => fast_mana, "cards" => f.evidence_by_tag["fast_mana"] || [] },
        "low_curve_count" => low_curve,
        "mana_curve" => f.mana_curve
      }
    end

    def interaction_evidence(f, removal, counters, wipes, protection)
      {
        "removal" => { "count" => removal, "cards" => f.evidence_by_tag["removal"] || [] },
        "stack_interaction" => { "count" => counters, "cards" => f.evidence_by_tag["stack_interaction"] || [] },
        "board_wipes" => { "count" => wipes, "cards" => f.evidence_by_tag["board_wipe"] || [] },
        "protection" => { "count" => protection, "cards" => f.evidence_by_tag["protection"] || [] }
      }
    end

    def consistency_evidence(f, card_draw, tutors, lands, mana_sources)
      {
        "card_draw" => { "count" => card_draw, "cards" => f.evidence_by_tag["card_draw"] || [] },
        "tutors" => { "count" => tutors, "cards" => f.evidence_by_tag["tutor"] || [] },
        "lands" => lands,
        "mana_sources" => mana_sources,
        "missing_oracle_count" => f.missing_oracle_count
      }
    end

    def build_recommendations(f)
      recs = []
      mana_sources = f.mana_source_count
      lands = f.land_count
      card_draw = f.role_counts.fetch("card_draw", 0)
      removal = f.role_counts.fetch("removal", 0)
      ramp = f.role_counts.fetch("ramp", 0) + f.role_counts.fetch("fast_mana", 0)

      if mana_sources < 36
        recs << {
          "category" => "mana",
          "title" => "Add mana sources",
          "detail" => "Deck has #{mana_sources} mana sources (lands + ramp). Aim for 36–38 at this curve."
        }
      end

      if lands < 34
        recs << {
          "category" => "lands",
          "title" => "Add lands",
          "detail" => "Only #{lands} lands. Consider 34–38 lands for a Commander deck."
        }
      end

      if ramp < 8
        recs << {
          "category" => "ramp",
          "title" => "Add ramp",
          "detail" => "Found #{ramp} ramp/fast-mana pieces. Most Commander decks want 8–12."
        }
      end

      if card_draw < 8
        recs << {
          "category" => "draw",
          "title" => "Add card draw",
          "detail" => "Found #{card_draw} card-draw pieces. 8–12 is a healthy floor."
        }
      end

      if removal < 6
        recs << {
          "category" => "interaction",
          "title" => "Add interaction",
          "detail" => "Found #{removal} removal pieces. Aim for 8–10 to handle threats."
        }
      end

      salt_total = f.salt_counts.values.sum
      if salt_total >= 4
        top_salt = f.salt_counts.max_by { |_, count| count }
        recs << {
          "category" => "salt",
          "title" => "Consider salt-reduction swaps",
          "detail" => "Salt drivers: #{salt_total} cards. Top: #{slug_to_label(top_salt.first)} (#{top_salt.last})."
        }
      end

      recs
    end

    def saltlike_to_ten(raw)
      case raw
      when 0 then 0
      when 0...2 then 1
      when 2...4 then 2
      when 4...6 then 3
      when 6...9 then 4
      when 9...12 then 5
      when 12...16 then 6
      when 16...20 then 7
      when 20...26 then 8
      when 26...34 then 9
      else 10
      end
    end

    def severity_weight_for(slug)
      @resolved_severity_lookup ||= @severity_lookup || load_severity_lookup
      severity = @resolved_severity_lookup[slug] || "moderate"
      SEVERITY_WEIGHTS[severity] || 1.0
    end

    def load_severity_lookup
      CardTag.where(slug: Decks::FeatureExtractor::SALT_TAG_SLUGS).pluck(:slug, :default_severity).to_h
    end

    def slug_to_label(slug)
      slug.to_s.delete_prefix("salt_driver_").delete_prefix("social_friction_").tr("_", " ").capitalize
    end

    def band(value, thresholds)
      thresholds.reverse.each do |threshold, points|
        return points if value >= threshold
      end
      0
    end

    def clamp10(n)
      [ [ n.to_i, 1 ].max, 10 ].min
    end
  end
end
