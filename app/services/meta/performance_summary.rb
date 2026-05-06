module Meta
  class PerformanceSummary
    OutcomeEntry = Struct.new(
      :seat,
      :result,
      :deck_id,
      :deck_name,
      :commander_names,
      :played_on,
      :turns,
      :win_condition,
      :outcome,
      :revision_key,
      :deck_updated_at,
      :deck_card_count,
      keyword_init: true
    )

    StatLine = Struct.new(
      :games,
      :wins,
      :losses,
      :draws,
      :win_rate,
      :average_turns,
      :last_played_on,
      :confidence_label,
      keyword_init: true
    )

    RevisionLine = Struct.new(
      :revision_key,
      :deck_updated_at,
      :deck_card_count,
      :stats,
      keyword_init: true
    )

    CommanderLine = Struct.new(
      :name,
      :games,
      :wins,
      :draws,
      :win_rate,
      :average_turns,
      :last_played_on,
      :confidence_label,
      :trend_label,
      keyword_init: true
    )

    PromptLine = Struct.new(
      :pod_number,
      :player_name,
      :deck,
      :deck_name,
      :outcome,
      :prompts,
      keyword_init: true
    )

    def self.for_user(user)
      new(user)
    end

    def initialize(user)
      @user = user
    end

    def deck_performance(deck)
      stats_for(entries.select { |entry| entry.deck_id == deck.id })
    end

    def revision_performance(deck)
      entries.select { |entry| entry.deck_id == deck.id }
             .group_by(&:revision_key)
             .map do |revision_key, rows|
               latest = rows.max_by { |row| row.played_on || Date.new(1, 1, 1) }
               RevisionLine.new(
                 revision_key: revision_key,
                 deck_updated_at: latest.deck_updated_at,
                 deck_card_count: latest.deck_card_count,
                 stats: stats_for(rows)
               )
             end
             .sort_by { |line| line.stats.last_played_on || Date.new(1, 1, 1) }
             .reverse
    end

    def commander_meta(limit: 8)
      entries
        .flat_map do |entry|
          Array(entry.commander_names).map { |name| [ ApplicationRecord.normalize_card_name(name), name, entry ] }
        end
        .reject { |normalized_name, _name, _entry| normalized_name.blank? }
        .group_by(&:first)
        .map { |_normalized_name, rows| commander_line(rows) }
        .sort_by { |line| [ line.games, line.win_rate || 0, line.last_played_on || Date.new(1, 1, 1) ] }
        .reverse
        .first(limit)
    end

    def post_game_prompts(game_night)
      seats = game_night.game_night_pod_seats.includes(:player, :deck).to_a
      results_by_pod = game_night.game_night_pod_results.index_by(&:pod_number)

      seats.filter_map do |seat|
        result = results_by_pod[seat.pod_number]
        next unless result

        outcome = outcome_for(seat, result)
        PromptLine.new(
          pod_number: seat.pod_number,
          player_name: seat.player.name,
          deck: seat.deck,
          deck_name: seat.deck_name_snapshot,
          outcome: outcome,
          prompts: prompts_for(seat, result, outcome)
        )
      end
    end

    private
      attr_reader :user

      def entries
        @entries ||= begin
          seats = GameNightPodSeat.joins(:game_night)
                                  .where(game_nights: { user_id: user.id })
                                  .includes(:player, :deck, :game_night)
                                  .to_a
          result_lookup = GameNightPodResult.where(game_night_id: seats.map(&:game_night_id).uniq)
                                            .index_by { |result| [ result.game_night_id, result.pod_number ] }

          seats.filter_map do |seat|
            result = result_lookup[[ seat.game_night_id, seat.pod_number ]]
            next unless result

            snapshot = seat.analysis_snapshot || {}
            OutcomeEntry.new(
              seat: seat,
              result: result,
              deck_id: seat.deck_id,
              deck_name: seat.deck_name_snapshot.presence || seat.deck.name,
              commander_names: Array(seat.commander_names_snapshot),
              played_on: seat.game_night.played_on,
              turns: result.turns,
              win_condition: result.win_condition,
              outcome: outcome_for(seat, result),
              revision_key: revision_key(snapshot),
              deck_updated_at: snapshot.dig("deck_updated_at"),
              deck_card_count: snapshot.dig("deck_card_count")
            )
          end
        end
      end

      def stats_for(rows)
        games = rows.size
        wins = rows.count { |row| row.outcome == "win" }
        draws = rows.count { |row| row.outcome == "draw" }
        losses = games - wins - draws
        turn_values = rows.filter_map(&:turns)

        StatLine.new(
          games: games,
          wins: wins,
          losses: losses,
          draws: draws,
          win_rate: games.positive? ? (wins.to_f / games) : nil,
          average_turns: turn_values.any? ? (turn_values.sum.to_f / turn_values.size) : nil,
          last_played_on: rows.filter_map(&:played_on).max,
          confidence_label: confidence_label(games)
        )
      end

      def commander_line(rows)
        names = rows.map(&:second)
        stat_rows = rows.map(&:third)
        stats = stats_for(stat_rows)

        CommanderLine.new(
          name: names.tally.max_by { |_name, count| count }.first,
          games: stats.games,
          wins: stats.wins,
          draws: stats.draws,
          win_rate: stats.win_rate,
          average_turns: stats.average_turns,
          last_played_on: stats.last_played_on,
          confidence_label: stats.confidence_label,
          trend_label: trend_label(stat_rows)
        )
      end

      def trend_label(rows)
        sorted = rows.sort_by { |row| row.played_on || Date.new(1, 1, 1) }.reverse
        return "sample too thin" if sorted.size < 6

        recent = stats_for(sorted.first(3)).win_rate.to_f
        prior = stats_for(sorted.drop(3).first(3)).win_rate.to_f
        delta = recent - prior

        if delta >= 0.25
          "rising recently"
        elsif delta <= -0.25
          "cooling recently"
        else
          "steady recently"
        end
      end

      def prompts_for(seat, result, outcome)
        prompts = [
          "What actually caused this #{outcome}?",
          "Were there dead draws, stranded cards, or cards you wished were in hand?"
        ]
        prompts << "This ended on turn #{result.turns}; was it a short-game outlier or the deck's normal speed?" if result.turns.present? && result.turns <= 5

        ownership = Collections::Ownership.for_deck(user: user, deck: seat.deck)
        if ownership.missing_count.positive?
          prompts << "Did any missing collection cards matter? #{ownership.missing_entries.first(3).map(&:name).join(', ')} are still uncovered."
        end

        prompts
      end

      def outcome_for(seat, result)
        return "draw" if result.draw?
        return "win" if result.winner_player_id == seat.player_id

        "loss"
      end

      def revision_key(snapshot)
        [
          snapshot.dig("deck_updated_at").presence || "unknown-time",
          snapshot.dig("deck_card_count").presence || "unknown-count",
          snapshot.dig("analysis_run_id").presence || snapshot.dig("scorecard", "analysis_run_id").presence || "no-analysis"
        ].join("/")
      end

      def confidence_label(games)
        case games
        when 0
          "no games"
        when 1..4
          "thin sample"
        when 5..9
          "early signal"
        else
          "established sample"
        end
      end
  end
end
