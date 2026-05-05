module CommanderFormat
  class LegalityChecker
    DECK_SIZE_TOTAL = 100
    MAX_COMMANDERS = 2

    BASIC_LAND_NORMALIZED_NAMES = [
      "plains", "island", "swamp", "mountain", "forest", "wastes",
      "snow covered plains", "snow covered island", "snow covered swamp",
      "snow covered mountain", "snow covered forest", "snow covered wastes"
    ].freeze

    SINGLETON_EXEMPT_LIMITS = {
      "relentless rats" => Float::INFINITY,
      "rat colony" => Float::INFINITY,
      "shadowborn apostle" => Float::INFINITY,
      "persistent petitioners" => Float::INFINITY,
      "dragon s approach" => Float::INFINITY,
      "slime against humanity" => Float::INFINITY,
      "hare apparent" => Float::INFINITY,
      "templar knight" => Float::INFINITY,
      "seven dwarves" => 7,
      "nazgul" => 9
    }.freeze

    SEVERITIES = %w[error warning info].freeze

    Issue = Struct.new(:code, :severity, :message, :card_name, :metadata, keyword_init: true)

    Result = Struct.new(:legal, :issues, :checked_at, :snapshot, keyword_init: true) do
      def legal?
        legal
      end

      def errors
        issues.select { |i| i.severity == "error" }
      end

      def warnings
        issues.select { |i| i.severity == "warning" }
      end

      def infos
        issues.select { |i| i.severity == "info" }
      end

      def to_h
        {
          legal: legal?,
          checked_at: checked_at,
          snapshot_id: snapshot&.id,
          snapshot_source: snapshot&.source,
          snapshot_effective_on: snapshot&.effective_on,
          issues: issues.map do |i|
            i.to_h.compact.transform_keys(&:to_s)
          end
        }
      end
    end

    def initialize(snapshot: LegalitySnapshot.current_commander, oracle_lookup: OracleCardLookup.new)
      @snapshot = snapshot
      @oracle_lookup = oracle_lookup
    end

    def check(deck)
      raise ArgumentError, "Commander legality requires a deck" unless deck

      commander_entries = deck_commander_entries(deck)
      mainboard_entries = deck_mainboard_entries(deck)

      issues = []
      issues.concat(check_snapshot_present)
      issues.concat(check_format(deck))
      issues.concat(check_commander_count(commander_entries))
      issues.concat(check_deck_size(commander_entries, mainboard_entries))
      issues.concat(check_singleton(commander_entries, mainboard_entries))
      issues.concat(check_banned(commander_entries + mainboard_entries))
      issues.concat(check_commander_typeline(commander_entries))
      issues.concat(check_color_identity(commander_entries, mainboard_entries))

      Result.new(
        legal: issues.none? { |i| i.severity == "error" },
        issues: issues,
        checked_at: Time.current,
        snapshot: @snapshot
      )
    end

    private

    def deck_commander_entries(deck)
      deck.commanders.to_a.map do |commander|
        Entry.new(
          name: commander.name,
          normalized_name: ApplicationRecord.normalize_card_name(commander.name),
          quantity: 1,
          board: "commander",
          oracle_card: commander.oracle_card
        )
      end
    end

    def deck_mainboard_entries(deck)
      deck.deck_cards.select { |dc| dc.board == "main" || dc.board == "commander" }.map do |dc|
        Entry.new(
          name: dc.name,
          normalized_name: dc.normalized_name.presence || ApplicationRecord.normalize_card_name(dc.name),
          quantity: dc.quantity,
          board: dc.board,
          oracle_card: dc.oracle_card
        )
      end
    end

    Entry = Struct.new(:name, :normalized_name, :quantity, :board, :oracle_card, keyword_init: true) do
      def basic_land?
        BASIC_LAND_NORMALIZED_NAMES.include?(normalized_name)
      end

      def singleton_limit
        SINGLETON_EXEMPT_LIMITS[normalized_name] || 1
      end
    end

    def check_snapshot_present
      return [] if @snapshot

      [
        Issue.new(
          code: "missing_snapshot",
          severity: "warning",
          message: "No Commander legality snapshot is loaded; banlist and category checks were skipped."
        )
      ]
    end

    def check_format(deck)
      return [] if deck.format == "commander"

      [
        Issue.new(
          code: "wrong_format",
          severity: "error",
          message: "Deck format must be 'commander' to run Commander legality checks (was #{deck.format.inspect})."
        )
      ]
    end

    def check_commander_count(commander_entries)
      issues = []
      if commander_entries.empty?
        issues << Issue.new(
          code: "missing_commander",
          severity: "error",
          message: "Commander decks must declare at least one commander."
        )
      elsif commander_entries.size > MAX_COMMANDERS
        issues << Issue.new(
          code: "too_many_commanders",
          severity: "error",
          message: "Commander decks may declare at most #{MAX_COMMANDERS} commanders (Partner). Found #{commander_entries.size}."
        )
      end
      issues
    end

    def check_deck_size(commander_entries, mainboard_entries)
      total = commander_entries.sum(&:quantity) + mainboard_entries.sum(&:quantity)
      return [] if total == DECK_SIZE_TOTAL

      severity = total < DECK_SIZE_TOTAL ? "error" : "error"
      [
        Issue.new(
          code: "wrong_deck_size",
          severity: severity,
          message: "Commander decks must contain exactly #{DECK_SIZE_TOTAL} cards including the commander (found #{total}).",
          metadata: { "total" => total, "expected" => DECK_SIZE_TOTAL }
        )
      ]
    end

    def check_singleton(commander_entries, mainboard_entries)
      counts = Hash.new(0)
      (commander_entries + mainboard_entries).each do |entry|
        counts[entry.normalized_name] += entry.quantity
      end

      counts.flat_map do |normalized, count|
        next [] if BASIC_LAND_NORMALIZED_NAMES.include?(normalized)
        limit = SINGLETON_EXEMPT_LIMITS[normalized] || 1
        next [] if count <= limit

        display_name = pretty_name(normalized, mainboard_entries + commander_entries)
        [
          Issue.new(
            code: "singleton_violation",
            severity: "error",
            message: "Commander format limits #{display_name} to #{limit_label(limit)} (found #{count}).",
            card_name: display_name,
            metadata: { "count" => count, "limit" => (limit == Float::INFINITY ? nil : limit) }
          )
        ]
      end
    end

    def check_banned(entries)
      return [] unless @snapshot

      entries.filter_map do |entry|
        next if entry.basic_land?
        next unless @snapshot.banned_normalized_names.include?(entry.normalized_name)

        Issue.new(
          code: "banned_card",
          severity: "error",
          message: "#{entry.name} is on the Commander banned list (#{@snapshot.source}, effective #{@snapshot.effective_on}).",
          card_name: entry.name
        )
      end
    end

    def check_commander_typeline(commander_entries)
      commander_entries.flat_map do |entry|
        oracle = oracle_for(entry)
        next [ info_issue("commander_typeline_unknown", entry.name, "Could not verify commander type line; oracle data missing for #{entry.name}.") ] unless oracle

        type_line = oracle.type_line.to_s.downcase
        next [] if type_line.include?("legendary") && (type_line.include?("creature") || type_line.include?("planeswalker"))

        [
          Issue.new(
            code: "commander_invalid_typeline",
            severity: "error",
            message: "#{entry.name} cannot be a commander (type line: #{oracle.type_line.inspect}).",
            card_name: entry.name
          )
        ]
      end
    end

    def check_color_identity(commander_entries, mainboard_entries)
      commander_oracles = commander_entries.map { |e| oracle_for(e) }
      if commander_oracles.any?(&:nil?)
        return [
          info_issue(
            "color_identity_unknown",
            nil,
            "Skipped color identity check: oracle data missing for one or more commanders."
          )
        ]
      end

      identity = commander_oracles.flat_map { |o| Array(o.color_identity) }.compact.uniq.sort

      mainboard_entries.flat_map do |entry|
        next [] if entry.basic_land?
        oracle = oracle_for(entry)
        next [] unless oracle

        card_identity = Array(oracle.color_identity).compact.uniq
        offending = card_identity - identity
        next [] if offending.empty?

        [
          Issue.new(
            code: "color_identity_violation",
            severity: "error",
            message: "#{entry.name} contains #{offending.join("/")} which is outside the commander color identity (#{identity.join("/").presence || "colorless"}).",
            card_name: entry.name,
            metadata: { "card_identity" => card_identity, "commander_identity" => identity }
          )
        ]
      end
    end

    def oracle_for(entry)
      entry.oracle_card || @oracle_lookup.lookup(entry.normalized_name)
    end

    def info_issue(code, card_name, message)
      Issue.new(code: code, severity: "info", message: message, card_name: card_name)
    end

    def pretty_name(normalized, entries)
      entry = entries.find { |e| e.normalized_name == normalized }
      entry&.name || normalized
    end

    def limit_label(limit)
      limit == Float::INFINITY ? "any number" : "#{limit} #{'copy'.pluralize(limit)}"
    end
  end
end
