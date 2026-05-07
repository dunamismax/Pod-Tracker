module Decks
  class AnalysisExporter
    SCHEMA_VERSION = 1
    SCORE_AXES = [
      [ :power_score, "Power" ],
      [ :speed_score, "Speed" ],
      [ :interaction_score, "Interaction" ],
      [ :consistency_score, "Consistency" ],
      [ :salt_score, "Salt" ],
      [ :social_friction_score, "Social Friction" ]
    ].freeze

    def initialize(deck, run: nil, generated_at: Time.current)
      @deck = deck
      @run = run || deck.latest_deterministic_run
      @generated_at = generated_at
    end

    def present?
      @run&.scorecard.present?
    end

    def to_h
      payload = {
        schema_version: SCHEMA_VERSION,
        generated_at: iso(@generated_at),
        deck: {
          id: @deck.id,
          name: @deck.name,
          commander_names: @deck.commander_names,
          card_count: @deck.deck_cards.sum(:quantity)
        }
      }
      if present?
        payload[:analysis] = analysis_payload
      else
        payload[:analysis] = nil
      end
      payload
    end

    def to_json(*)
      JSON.pretty_generate(to_h)
    end

    def to_markdown
      lines = []
      lines << "# Deterministic analysis — #{@deck.name}"
      lines << ""
      lines << "_Exported #{@generated_at.utc.iso8601}_"
      lines << ""

      unless present?
        lines << "Deterministic analysis has not run for this deck yet."
        return lines.join("\n") + "\n"
      end

      scorecard = @run.scorecard
      bracket = scorecard.bracket_payload.is_a?(Hash) ? scorecard.bracket_payload : {}

      lines << "**Deck:** #{@deck.name}"
      lines << "**Commander:** #{@deck.commander_names.presence&.join(', ') || '—'}"
      lines << "**Cards:** #{@deck.deck_cards.sum(:quantity)}"
      lines << "**Rubric:** `#{@run.rubric_version}`"
      if scorecard.confidence.present?
        lines << "**Confidence:** #{(scorecard.confidence.to_f * 100).round}%"
      end
      if @run.completed_at
        lines << "**Computed:** #{@run.completed_at.utc.iso8601}"
      end
      lines << ""

      if scorecard.bracket.present?
        lines << "## Commander Bracket"
        lines << ""
        lines << "**#{bracket['headline'] || "Bracket #{scorecard.bracket}"} (sub-band: #{scorecard.bracket_sub_band || '—'})**"
        lines << ""
        if bracket["tagline"].present?
          lines << bracket["tagline"]
          lines << ""
        end
        if bracket["expected_min_turn"].present?
          lines << "Expected minimum turns: #{bracket['expected_min_turn']}+"
        else
          lines << "Any-turn wins permitted."
        end
        lines << ""

        gc_hits = Array(bracket["game_changers"])
        if gc_hits.any?
          lines << "### Game Changers (#{gc_hits.size})"
          lines << ""
          gc_hits.each do |gc|
            lines << "- #{gc['name']} — #{gc['category']&.humanize&.downcase}"
          end
          lines << ""
        end

        combo_pairs = Array(bracket["combo_pairs"])
        if combo_pairs.any?
          lines << "### Two-card combo lines"
          lines << ""
          combo_pairs.each do |pair|
            extra = pair["wins_immediately"] ? " — wins immediately" : ""
            lines << "- #{pair['name']}#{extra}"
          end
          lines << ""
        end

        restrictions = Array(bracket["restrictions"])
        if restrictions.any?
          lines << "### Bracket restrictions"
          lines << ""
          restrictions.each do |r|
            lines << "- **#{r['label']}** — #{r['status']} (allowance: #{r['allowance']}, found: #{r['actual']})"
            evidence = Array(r["evidence"])
            if evidence.any?
              lines << "  - #{evidence.join(', ')}"
            end
          end
          lines << ""
        end
      end

      lines << "## Sub-band evidence — six-axis scorecard"
      lines << ""
      lines << "| Axis | Score |"
      lines << "| --- | --- |"
      SCORE_AXES.each do |column, label|
        value = scorecard.public_send(column)
        lines << "| #{label} | #{value || '—'}/10 |"
      end
      lines << ""

      legality = @run.deterministic_snapshot.is_a?(Hash) ? @run.deterministic_snapshot["legality"] : nil
      if legality.present?
        lines << "## Commander legality"
        lines << ""
        lines << (legality["legal"] ? "Legal." : "Issues found.")
        if legality["snapshot_effective_on"].present?
          lines << ""
          lines << "Snapshot #{legality['snapshot_source']}, effective #{legality['snapshot_effective_on']}."
        end
        issues = Array(legality["issues"])
        if issues.any?
          lines << ""
          issues.each do |issue|
            note = issue["card_name"].present? ? " (#{issue['card_name']})" : ""
            lines << "- **#{issue['severity']}** — #{issue['message']}#{note}"
          end
        end
        lines << ""
      end

      recs = Array(scorecard.improvement_suggestions)
      if recs.any?
        lines << "## Suggestions"
        lines << ""
        recs.each do |rec|
          ownership = rec["ownership"] || {}
          line = "- **#{rec['title']}** — #{rec['detail']}"
          if ownership["label"].present?
            line += " _(#{ownership['label']}: #{ownership['detail']})_"
          end
          lines << line
        end
        lines << ""
      end

      lines.join("\n") + "\n"
    end

    def filename(extension)
      slug = @deck.name.to_s.gsub(/[^a-z0-9]+/i, "-").downcase.gsub(/^-+|-+$/, "").presence || "deck"
      stamp = @generated_at.utc.strftime("%Y%m%dT%H%M%SZ")
      "ideal-magic-analysis-#{slug}-#{stamp}.#{extension}"
    end

    private
      def analysis_payload
        scorecard = @run.scorecard
        {
          run_id: @run.id,
          rubric_version: @run.rubric_version,
          completed_at: iso(@run.completed_at),
          confidence: scorecard.confidence,
          bracket: scorecard.bracket,
          bracket_sub_band: scorecard.bracket_sub_band,
          bracket_payload: scorecard.bracket_payload,
          scores: SCORE_AXES.each_with_object({}) do |(column, _label), memo|
            memo[column] = scorecard.public_send(column)
          end,
          improvement_suggestions: Array(scorecard.improvement_suggestions),
          legality: @run.deterministic_snapshot.is_a?(Hash) ? @run.deterministic_snapshot["legality"] : nil
        }
      end

      def iso(value)
        value&.utc&.iso8601
      end
  end
end
