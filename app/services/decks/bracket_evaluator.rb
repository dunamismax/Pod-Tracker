require "json"

module Decks
  # Maps a Commander deck to a 1–5 bracket on the official Wizards Commander
  # Brackets system (beta, last referenced data file: 2026-02-09).
  #
  # The evaluator is deterministic. It looks at:
  #   * The Game Changers list (canonical, source-controlled).
  #   * Mass land denial cards (curated salt-driver tag).
  #   * Extra-turn cards (curated salt-driver tag).
  #   * Two-card win combos (curated combo pair list).
  #   * Combo / stax / fast-mana / tutor density from the deck feature vector.
  #   * The deterministic 0–10 power and speed scores for sub-band placement.
  #
  # Output is a `Result` struct that downstream code persists to the scorecard
  # row and renders on the deck show page. The structure is stable enough to
  # diff across deck revisions and to copy into a Rule 0 brief.
  class BracketEvaluator
    BRACKETS = {
      1 => {
        "label" => "Exhibition",
        "tagline" => "Theme-first showcase Commander.",
        "expected_min_turn" => 9,
        "max_game_changers" => 0,
        "allows_mass_land_denial" => false,
        "allows_chained_extra_turns" => false,
        "allows_any_extra_turns" => false,
        "allows_two_card_combo" => false,
        "two_card_combo_min_turn" => nil
      },
      2 => {
        "label" => "Core",
        "tagline" => "Casual, functional, low-pressure Commander.",
        "expected_min_turn" => 8,
        "max_game_changers" => 0,
        "allows_mass_land_denial" => false,
        "allows_chained_extra_turns" => false,
        "allows_any_extra_turns" => true,
        "allows_two_card_combo" => false,
        "two_card_combo_min_turn" => nil
      },
      3 => {
        "label" => "Upgraded",
        "tagline" => "Tuned casual Commander with sharper interaction.",
        "expected_min_turn" => 6,
        "max_game_changers" => 3,
        "allows_mass_land_denial" => false,
        "allows_chained_extra_turns" => false,
        "allows_any_extra_turns" => true,
        "allows_two_card_combo" => true,
        "two_card_combo_min_turn" => 6
      },
      4 => {
        "label" => "Optimized",
        "tagline" => "High-power, fast, lethal — but not built for the cEDH metagame.",
        "expected_min_turn" => 4,
        "max_game_changers" => nil,
        "allows_mass_land_denial" => true,
        "allows_chained_extra_turns" => true,
        "allows_any_extra_turns" => true,
        "allows_two_card_combo" => true,
        "two_card_combo_min_turn" => nil
      },
      5 => {
        "label" => "cEDH",
        "tagline" => "Competitive Commander, built for a known metagame.",
        "expected_min_turn" => nil,
        "max_game_changers" => nil,
        "allows_mass_land_denial" => true,
        "allows_chained_extra_turns" => true,
        "allows_any_extra_turns" => true,
        "allows_two_card_combo" => true,
        "two_card_combo_min_turn" => nil
      }
    }.freeze

    GAME_CHANGER_CATALOG_PATH =
      Rails.root.join("db/seeds/commander/brackets/game_changers.json").freeze

    TWO_CARD_COMBO_CATALOG_PATH =
      Rails.root.join("db/seeds/commander/brackets/two_card_combos.json").freeze

    Result = Struct.new(
      :bracket, :label, :tagline, :sub_band, :expected_min_turn,
      :game_changers, :restrictions, :combo_pairs, :evidence, :headline, :version,
      keyword_init: true
    ) do
      def to_h
        {
          "bracket" => bracket,
          "label" => label,
          "tagline" => tagline,
          "sub_band" => sub_band,
          "expected_min_turn" => expected_min_turn,
          "game_changers" => game_changers,
          "restrictions" => restrictions,
          "combo_pairs" => combo_pairs,
          "evidence" => evidence,
          "headline" => headline,
          "version" => version
        }
      end
    end

    def self.catalog_version
      JSON.parse(File.read(GAME_CHANGER_CATALOG_PATH))["version"]
    end

    def initialize(catalog: nil, combo_catalog: nil)
      @catalog = catalog || JSON.parse(File.read(GAME_CHANGER_CATALOG_PATH))
      @combo_catalog = combo_catalog || JSON.parse(File.read(TWO_CARD_COMBO_CATALOG_PATH))
      @gc_index = build_gc_index(@catalog)
    end

    # `features`: a `Decks::FeatureExtractor::Result` (or hash with the same shape).
    # `scorecard`: an object that responds to power_score and speed_score (the
    #   already-computed deterministic 0–10 scorecard). Used only for sub-band
    #   placement and as one of several signals for Bracket 1 detection.
    # `card_names`: array of normalized strings present in the mainboard +
    #   command zone. We use the deck cards directly so this stays decoupled
    #   from feature extraction.
    def call(features:, card_names:, scorecard: nil)
      normalized = card_names.compact.map { |n| ApplicationRecord.normalize_card_name(n) }.uniq

      gc_hits = detect_game_changers(normalized)
      mld_count = features.salt_counts.fetch("salt_driver_mass_land_denial", 0).to_i
      mld_evidence = Array(features.evidence_by_tag["salt_driver_mass_land_denial"])
      extra_turn_count = features.salt_counts.fetch("salt_driver_extra_turns", 0).to_i
      extra_turn_evidence = Array(features.evidence_by_tag["salt_driver_extra_turns"])
      combo_pairs = detect_two_card_combos(normalized)
      combo_count = features.role_counts.fetch("combo", 0).to_i
      stax_count = features.role_counts.fetch("stax", 0).to_i
      fast_mana_count = features.role_counts.fetch("fast_mana", 0).to_i
      tutor_count = features.role_counts.fetch("tutor", 0).to_i

      bracket = place(
        gc_hits: gc_hits,
        mld_count: mld_count,
        extra_turn_count: extra_turn_count,
        combo_pairs: combo_pairs,
        combo_count: combo_count,
        stax_count: stax_count,
        fast_mana_count: fast_mana_count,
        tutor_count: tutor_count,
        power_score: scorecard&.power_score.to_i,
        win_conditions: features.role_counts.fetch("win_condition", 0).to_i,
        interaction_count: features.role_counts.fetch("removal", 0).to_i +
                          features.role_counts.fetch("stack_interaction", 0).to_i +
                          features.role_counts.fetch("board_wipe", 0).to_i
      )

      restrictions = restrictions_payload(
        bracket: bracket,
        gc_hits: gc_hits,
        mld_count: mld_count,
        mld_evidence: mld_evidence,
        extra_turn_count: extra_turn_count,
        extra_turn_evidence: extra_turn_evidence,
        combo_pairs: combo_pairs,
        combo_count: combo_count
      )

      sub_band = sub_band_for(bracket, scorecard, fast_mana_count, tutor_count, combo_count, gc_hits.size)

      meta = BRACKETS.fetch(bracket)

      Result.new(
        bracket: bracket,
        label: meta["label"],
        tagline: meta["tagline"],
        sub_band: sub_band,
        expected_min_turn: meta["expected_min_turn"],
        game_changers: gc_hits,
        restrictions: restrictions,
        combo_pairs: combo_pairs,
        evidence: {
          "fast_mana" => fast_mana_count,
          "tutors" => tutor_count,
          "stax" => stax_count,
          "combo_pieces" => combo_count,
          "mass_land_denial" => mld_count,
          "extra_turns" => extra_turn_count,
          "game_changer_count" => gc_hits.size
        },
        headline: headline_for(bracket, sub_band, gc_hits, combo_pairs),
        version: @catalog["version"]
      )
    end

    private

    def build_gc_index(catalog)
      Array(catalog["cards"]).each_with_object({}) do |entry, idx|
        idx[ApplicationRecord.normalize_card_name(entry["name"])] = entry
      end
    end

    def detect_game_changers(normalized)
      normalized.filter_map do |name|
        meta = @gc_index[name]
        next unless meta
        { "name" => meta["name"], "category" => meta["category"] }
      end.uniq { |m| m["name"] }
    end

    def detect_two_card_combos(normalized)
      Array(@combo_catalog["pairs"]).filter_map do |pair|
        left_hits = Array(pair["left"]).select { |n| normalized.include?(ApplicationRecord.normalize_card_name(n)) }
        right_hits = Array(pair["right"]).select { |n| normalized.include?(ApplicationRecord.normalize_card_name(n)) }
        next if left_hits.empty? || right_hits.empty?

        {
          "name" => pair["name"],
          "left" => left_hits,
          "right" => right_hits,
          "wins_immediately" => pair["wins_immediately"] == true
        }
      end
    end

    # Bracket placement reads the published gates as a one-way ladder. We
    # walk top-down: any feature that disqualifies a deck from a given
    # bracket pushes it strictly higher.
    def place(gc_hits:, mld_count:, extra_turn_count:, combo_pairs:, combo_count:, stax_count:, fast_mana_count:, tutor_count:, power_score:, win_conditions:, interaction_count:)
      gc_count = gc_hits.size
      chained_extra_turns = extra_turn_count >= 2
      has_mld = mld_count >= 1

      # Bracket 5 (cEDH) is reserved for decks that look like competitive
      # builds: deep tutor + fast mana + GC stack with combo pressure.
      cedh_signals = gc_count >= 6 && fast_mana_count >= 4 && tutor_count >= 5 && (combo_count >= 3 || combo_pairs.any?)
      return 5 if cedh_signals

      # Bracket 4: optimized non-cEDH. Allowed everything except cEDH intent.
      # We push to 4 if any of the high-power signals are present that B3
      # rules out.
      pushed_to_four =
        gc_count > 3 ||
        has_mld ||
        chained_extra_turns ||
        (combo_pairs.any? && combo_pairs.any? { |p| p["wins_immediately"] }) ||
        (stax_count >= 4 && fast_mana_count >= 3)

      return 4 if pushed_to_four

      # Bracket 3: tuned casual. Up to 3 GCs allowed, no MLD, no chained
      # extra turns, no early two-card game-enders. A single combo pair is
      # tolerated as long as it isn't an immediate-win combo.
      pushed_to_three =
        gc_count.between?(1, 3) ||
        combo_count >= 3 ||
        combo_pairs.any? ||
        tutor_count >= 4 ||
        fast_mana_count >= 2 ||
        stax_count >= 2

      return 3 if pushed_to_three

      # Bracket 1: theme-first showcase. Reserved for decks that genuinely
      # look like expressive projects, not "Bracket 2 with no extra turns."
      # Heuristic: low power score, light interaction, no win-condition
      # density, no extra turns, no combos.
      if exhibition_shaped?(
        extra_turn_count: extra_turn_count,
        combo_count: combo_count,
        power_score: power_score,
        win_conditions: win_conditions,
        interaction_count: interaction_count,
        tutor_count: tutor_count,
        fast_mana_count: fast_mana_count
      )
        return 1
      end

      # Bracket 2: casual core. Default landing spot for a deck with a plan
      # but no GCs, no MLD, no chained extra turns, no intentional two-card
      # game-ending combos. A single splashy extra-turn spell is fine.
      2
    end

    def exhibition_shaped?(extra_turn_count:, combo_count:, power_score:, win_conditions:, interaction_count:, tutor_count:, fast_mana_count:)
      extra_turn_count.zero? &&
        combo_count.zero? &&
        tutor_count.zero? &&
        fast_mana_count <= 1 &&
        power_score <= 3 &&
        interaction_count <= 4 &&
        win_conditions <= 1
    end

    def restrictions_payload(bracket:, gc_hits:, mld_count:, mld_evidence:, extra_turn_count:, extra_turn_evidence:, combo_pairs:, combo_count:)
      meta = BRACKETS.fetch(bracket)
      list = []

      # Game Changers
      gc_max = meta["max_game_changers"]
      gc_count = gc_hits.size
      list << {
        "key" => "game_changers",
        "label" => "Game Changers",
        "status" => gc_violation_status(gc_max, gc_count),
        "allowance" => gc_max.nil? ? "any" : gc_max,
        "actual" => gc_count,
        "evidence" => gc_hits.first(8).map { |g| g["name"] }
      }

      # Mass land denial
      list << {
        "key" => "mass_land_denial",
        "label" => "Mass land denial",
        "status" => meta["allows_mass_land_denial"] ? (mld_count.zero? ? "absent" : "present_allowed") : (mld_count.zero? ? "ok" : "violation"),
        "allowance" => meta["allows_mass_land_denial"] ? "allowed" : "not allowed",
        "actual" => mld_count,
        "evidence" => mld_evidence.first(8)
      }

      # Extra turns
      chained = extra_turn_count >= 2
      extra_status =
        if meta["allows_chained_extra_turns"]
          extra_turn_count.zero? ? "absent" : "present_allowed"
        elsif !meta["allows_any_extra_turns"]
          extra_turn_count.zero? ? "ok" : "violation"
        else
          chained ? "violation" : (extra_turn_count.zero? ? "ok" : "ok_singleton")
        end
      list << {
        "key" => "extra_turns",
        "label" => "Extra turns",
        "status" => extra_status,
        "allowance" => extra_turn_allowance_label(meta),
        "actual" => extra_turn_count,
        "evidence" => extra_turn_evidence.first(8)
      }

      # Two-card game-ending combos
      combo_status =
        if !meta["allows_two_card_combo"]
          combo_pairs.any? || combo_count >= 3 ? "violation" : "ok"
        elsif meta["two_card_combo_min_turn"] && combo_pairs.any? { |p| p["wins_immediately"] }
          "violation"
        else
          combo_pairs.any? ? "present_allowed" : "ok"
        end
      list << {
        "key" => "two_card_combos",
        "label" => "Two-card game-ending combos",
        "status" => combo_status,
        "allowance" => combo_allowance_label(meta),
        "actual" => combo_pairs.size,
        "evidence" => combo_pairs.map { |p| p["name"] }
      }

      list
    end

    def gc_violation_status(max, count)
      return "any_allowed" if max.nil?
      return "ok" if count.zero?
      return count <= max ? "ok" : "violation" if max.positive?
      "violation"
    end

    def extra_turn_allowance_label(meta)
      return "allowed" if meta["allows_chained_extra_turns"]
      return "not allowed" unless meta["allows_any_extra_turns"]
      "single splashy turn only"
    end

    def combo_allowance_label(meta)
      return "any" unless meta["allows_two_card_combo"] == false || meta["two_card_combo_min_turn"]
      return "not allowed" unless meta["allows_two_card_combo"]
      "tolerated after turn #{meta['two_card_combo_min_turn']}"
    end

    # Sub-band reads the deterministic 0–10 power score relative to the
    # bracket's typical band. Brackets 3–5 are wide; brackets 1–2 are narrow.
    def sub_band_for(bracket, scorecard, fast_mana, tutors, combos, gc_count)
      power = scorecard&.power_score.to_i
      case bracket
      when 1
        "low"
      when 2
        return "high" if power >= 6
        return "mid" if power >= 4
        "low"
      when 3
        return "high" if gc_count >= 3 || tutors >= 4 || power >= 7
        return "mid" if gc_count >= 1 || tutors >= 2 || power >= 5
        "low"
      when 4
        return "high" if gc_count >= 6 && fast_mana >= 3
        return "low" if power <= 6
        "mid"
      when 5
        "mid"
      end
    end

    def headline_for(bracket, sub_band, gc_hits, combo_pairs)
      meta = BRACKETS.fetch(bracket)
      base = "Bracket #{bracket} · #{meta['label']}"
      sub_label = sub_band == "mid" ? "" : "#{sub_band.capitalize}-#{meta['label'].downcase} "
      summary = []
      summary << "#{gc_hits.size} Game Changer#{'s' unless gc_hits.size == 1}" if gc_hits.any?
      summary << "#{combo_pairs.size} two-card combo#{'s' unless combo_pairs.size == 1}" if combo_pairs.any?
      tail = summary.empty? ? meta["tagline"] : summary.join(" · ")
      "#{sub_label}#{base} — #{tail}"
    end
  end
end
