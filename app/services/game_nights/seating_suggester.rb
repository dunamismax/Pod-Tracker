module GameNights
  class SeatingSuggester
    MAX_POD_SIZE = 4

    Candidate = Struct.new(:player, :deck, :analysis_run, :bracket, :power_score, keyword_init: true)

    def self.call(game_night)
      new(game_night).call
    end

    def initialize(game_night)
      @game_night = game_night
    end

    def call
      candidates = build_candidates
      return [] if candidates.empty?

      pod_sizes = pod_sizes_for(candidates.size)
      pod_rows = pod_sizes.map.with_index { |_, index| [ index + 1, [] ] }.to_h

      ranked_candidates(candidates).each do |candidate|
        target_pod = pod_rows
          .select { |pod_number, rows| rows.size < pod_sizes[pod_number - 1] }
          .min_by { |_pod_number, rows| pod_strength(rows) }
          .first

        pod_rows[target_pod] << candidate
      end

      pod_rows.flat_map do |pod_number, rows|
        rows.each_with_index.map do |candidate, index|
          {
            "player_id" => candidate.player.id.to_s,
            "pod_number" => pod_number.to_s,
            "seat_number" => (index + 1).to_s
          }
        end
      end
    end

    private

    attr_reader :game_night

    def build_candidates
      deck_by_player_id = game_night.game_night_decks.includes(deck: { analysis_runs: :scorecard }).index_by(&:player_id)

      game_night.game_night_players.includes(:player).map do |check_in|
        night_deck = deck_by_player_id.fetch(check_in.player_id)
        run = night_deck.deck.latest_deterministic_run
        scorecard = run&.scorecard

        Candidate.new(
          player: check_in.player,
          deck: night_deck.deck,
          analysis_run: run,
          bracket: scorecard&.bracket || 1,
          power_score: scorecard&.power_score || 0
        )
      end
    end

    def ranked_candidates(candidates)
      candidates.sort_by do |candidate|
        [ -candidate.bracket, -candidate.power_score, candidate.player.name.downcase ]
      end
    end

    def pod_sizes_for(count)
      pod_count = (count.to_f / MAX_POD_SIZE).ceil
      base_size = count / pod_count
      extra = count % pod_count

      Array.new(pod_count) do |index|
        base_size + (index < extra ? 1 : 0)
      end
    end

    def pod_strength(rows)
      rows.sum { |candidate| (candidate.bracket * 100) + candidate.power_score }
    end
  end
end
