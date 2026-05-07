module Decks
  class AnalysisExporter
    SCHEMA_VERSION = 2
    SCORE_AXES = [
      [ :power_score, "Power" ],
      [ :speed_score, "Speed" ],
      [ :interaction_score, "Interaction" ],
      [ :consistency_score, "Consistency" ],
      [ :salt_score, "Salt" ],
      [ :social_friction_score, "Social Friction" ]
    ].freeze

    def initialize(deck, run: nil, ai_run: nil, generated_at: Time.current)
      @deck = deck
      @run = run || deck.latest_deterministic_run
      @ai_run = ai_run.nil? ? deck.latest_ai_run : ai_run
      @ai_evaluation = Decks::AiEvaluationPresenter.for(@ai_run)
      @generated_at = generated_at
    end

    def present?
      @run&.scorecard.present? || @ai_evaluation.present?
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
        },
        analysis: present? ? deterministic_payload : nil,
        ai_evaluation: ai_payload
      }
      payload
    end

    def to_json(*)
      JSON.pretty_generate(to_h)
    end

    def to_markdown
      lines = []
      lines << "# Analysis — #{@deck.name}"
      lines << ""
      lines << "_Exported #{@generated_at.utc.iso8601}_"
      lines << ""

      lines << "**Deck:** #{@deck.name}"
      lines << "**Commander:** #{@deck.commander_names.presence&.join(', ') || '—'}"
      lines << "**Cards:** #{@deck.deck_cards.sum(:quantity)}"
      lines << ""

      if @ai_evaluation.present?
        lines.concat(ai_markdown_lines)
        if @run&.scorecard.present?
          lines << "<details>"
          lines << "<summary>Preliminary deterministic read (used before AI evaluation; AI is now authoritative)</summary>"
          lines << ""
          lines.concat(deterministic_markdown_lines)
          lines << ""
          lines << "</details>"
          lines << ""
        end
      elsif @run&.scorecard.present?
        lines.concat(deterministic_markdown_lines)
      else
        lines << "Analysis has not run for this deck yet."
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
      def deterministic_payload
        return nil unless @run&.scorecard.present?
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

      def ai_payload
        return nil unless @ai_evaluation.present?
        {
          authoritative: true,
          run_id: @ai_run.id,
          prompt_version: @ai_evaluation.prompt_version,
          schema_version: Codex::DeckEvaluationSchema::VERSION,
          model: @ai_evaluation.model,
          completed_at: iso(@ai_evaluation.completed_at),
          stale: @ai_evaluation.stale?,
          summary: @ai_evaluation.summary,
          bracket: @ai_evaluation.bracket,
          axes: @ai_evaluation.axes,
          friction_drivers: @ai_evaluation.friction_drivers,
          rule_zero_talking_points: @ai_evaluation.talking_points,
          recommendations: @ai_evaluation.recommendations,
          legality_review: @ai_evaluation.legality_review
        }
      end

      def ai_markdown_lines
        lines = []
        lines << "## AI evaluation (Commander Brackets)"
        lines << ""
        if @ai_evaluation.prompt_version.present?
          lines << "_Prompt `#{@ai_evaluation.prompt_version}`#{@ai_evaluation.model.present? ? ", model `#{@ai_evaluation.model}`" : ''}." \
                   "#{@ai_evaluation.completed_at.present? ? " Completed #{@ai_evaluation.completed_at.utc.iso8601}." : ''}_"
          lines << ""
        end

        if @ai_evaluation.bracket_value.present?
          headline = @ai_evaluation.bracket_headline.presence || "Bracket #{@ai_evaluation.bracket_value}"
          lines << "**#{headline} (sub-band: #{@ai_evaluation.bracket_sub_band || '—'})**"
          lines << ""
          if @ai_evaluation.bracket_tagline.present?
            lines << @ai_evaluation.bracket_tagline
            lines << ""
          end
          if @ai_evaluation.expected_min_turn.present?
            lines << "Expected minimum turns: #{@ai_evaluation.expected_min_turn}+"
          else
            lines << "Any-turn wins permitted."
          end
          lines << ""
        end

        if @ai_evaluation.summary.present?
          lines << @ai_evaluation.summary
          lines << ""
        end

        if @ai_evaluation.bracket_evidence.any?
          lines << "### Bracket evidence"
          lines << ""
          @ai_evaluation.bracket_evidence.each { |line| lines << "- #{line}" }
          lines << ""
        end

        if @ai_evaluation.game_changers.any?
          lines << "### Game Changers (#{@ai_evaluation.game_changers.size})"
          lines << ""
          @ai_evaluation.game_changers.each do |gc|
            label = gc["category"].present? ? "#{gc['name']} — #{gc['category']&.humanize&.downcase}" : gc["name"]
            lines << "- #{label}"
          end
          lines << ""
        end

        if @ai_evaluation.restrictions.any?
          lines << "### Bracket restrictions"
          lines << ""
          @ai_evaluation.restrictions.each do |r|
            lines << "- **#{r['label']}** — #{r['status']}: #{r['detail']}"
            ev = Array(r["evidence"])
            lines << "  - #{ev.join(', ')}" if ev.any?
          end
          lines << ""
        end

        lines << "### Six-axis sub-band scorecard"
        lines << ""
        lines << "| Axis | Score | Notes |"
        lines << "| --- | --- | --- |"
        Codex::DeckEvaluationSchema::AXES.each do |key|
          axis = @ai_evaluation.axis(key)
          rationale = axis["rationale"].to_s.tr("\n|", " /")
          lines << "| #{key.humanize} | #{axis['value'] || '—'}/10 | #{rationale} |"
        end
        lines << ""

        if @ai_evaluation.friction_drivers.any?
          lines << "### Friction drivers"
          lines << ""
          @ai_evaluation.friction_drivers.each do |driver|
            lines << "- **#{driver['label']}** (#{driver['severity']}) — #{driver['explanation']}"
          end
          lines << ""
        end

        if @ai_evaluation.talking_points.any?
          lines << "### Rule 0 talking points"
          lines << ""
          @ai_evaluation.talking_points.each do |point|
            lines << "- **#{point['topic']}** — #{point['prompt']}"
          end
          lines << ""
        end

        if @ai_evaluation.recommendations.any?
          lines << "### Suggestions"
          lines << ""
          @ai_evaluation.recommendations.each do |rec|
            lines << "- **#{rec['title']}** — #{rec['detail']}"
          end
          lines << ""
        end

        if (legality = legality_data).present?
          lines.concat(legality_lines(legality))
        end

        if (lr = @ai_evaluation.legality_review).is_a?(Hash) && lr["note"].present?
          lines << "### AI legality note"
          lines << ""
          lines << lr["note"]
          flagged = Array(lr["flagged_cards"])
          if flagged.any?
            lines << ""
            lines << "Flagged: #{flagged.join(', ')}"
          end
          lines << ""
        end

        lines
      end

      def deterministic_markdown_lines
        lines = []
        lines << "## Deterministic analysis"
        lines << ""

        unless @run&.scorecard.present?
          lines << "Deterministic analysis has not run for this deck yet."
          lines << ""
          return lines
        end

        scorecard = @run.scorecard
        bracket = scorecard.bracket_payload.is_a?(Hash) ? scorecard.bracket_payload : {}

        lines << "**Rubric:** `#{@run.rubric_version}`"
        if scorecard.confidence.present?
          lines << "**Confidence:** #{(scorecard.confidence.to_f * 100).round}%"
        end
        if @run.completed_at
          lines << "**Computed:** #{@run.completed_at.utc.iso8601}"
        end
        lines << ""

        if scorecard.bracket.present?
          lines << "### Commander Bracket"
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
            lines << "#### Game Changers (#{gc_hits.size})"
            lines << ""
            gc_hits.each do |gc|
              lines << "- #{gc['name']} — #{gc['category']&.humanize&.downcase}"
            end
            lines << ""
          end

          combo_pairs = Array(bracket["combo_pairs"])
          if combo_pairs.any?
            lines << "#### Two-card combo lines"
            lines << ""
            combo_pairs.each do |pair|
              extra = pair["wins_immediately"] ? " — wins immediately" : ""
              lines << "- #{pair['name']}#{extra}"
            end
            lines << ""
          end

          restrictions = Array(bracket["restrictions"])
          if restrictions.any?
            lines << "#### Bracket restrictions"
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

        lines << "### Sub-band evidence — six-axis scorecard"
        lines << ""
        lines << "| Axis | Score |"
        lines << "| --- | --- |"
        SCORE_AXES.each do |column, label|
          value = scorecard.public_send(column)
          lines << "| #{label} | #{value || '—'}/10 |"
        end
        lines << ""

        if (legality = legality_data).present?
          lines.concat(legality_lines(legality))
        end

        recs = Array(scorecard.improvement_suggestions)
        if recs.any?
          lines << "### Suggestions"
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

        lines
      end

      def legality_data
        return nil unless @run&.deterministic_snapshot.is_a?(Hash)
        @run.deterministic_snapshot["legality"]
      end

      def legality_lines(legality)
        out = []
        out << "### Commander legality"
        out << ""
        out << (legality["legal"] ? "Legal." : "Issues found.")
        if legality["snapshot_effective_on"].present?
          out << ""
          out << "Snapshot #{legality['snapshot_source']}, effective #{legality['snapshot_effective_on']}."
        end
        issues = Array(legality["issues"])
        if issues.any?
          out << ""
          issues.each do |issue|
            note = issue["card_name"].present? ? " (#{issue['card_name']})" : ""
            out << "- **#{issue['severity']}** — #{issue['message']}#{note}"
          end
        end
        out << ""
        out
      end

      def iso(value)
        value&.utc&.iso8601
      end
  end
end
