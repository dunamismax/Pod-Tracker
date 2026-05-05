module GameNights
  class ResultRecorder
    Result = Struct.new(:success, :errors, keyword_init: true) do
      alias_method :success?, :success
    end

    def self.call(game_night, results:)
      new(game_night, results: results).call
    end

    def initialize(game_night, results:)
      @game_night = game_night
      @results = normalize_results(results)
      @errors = []
    end

    def call
      validate_results
      return Result.new(success: false, errors: errors) if errors.any?

      GameNight.transaction do
        game_night.game_night_pod_results.destroy_all

        results.each do |row|
          game_night.game_night_pod_results.create!(
            pod_number: row.fetch("pod_number").to_i,
            winner_player_id: winner_player_id(row),
            draw: draw?(row),
            turns: optional_integer(row["turns"]),
            win_condition: row["win_condition"].to_s.strip.presence,
            notes: row["notes"].to_s.strip.presence
          )
        end

        game_night.update!(status: "completed")
      end

      Result.new(success: true, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, errors: [ e.message ])
    end

    private

    attr_reader :game_night, :results, :errors

    def normalize_results(value)
      rows =
        case value
        when ActionController::Parameters
          value.to_unsafe_h.values
        when Hash
          value.values
        when Array
          value
        else
          []
        end

      rows.map { |row| row.to_h.transform_keys(&:to_s) }
    end

    def validate_results
      if results.empty?
        errors << "Record at least one pod result."
        return
      end

      expected_pods = game_night.game_night_pod_seats.reorder(nil).distinct.pluck(:pod_number).sort
      result_pods = results.filter_map { |row| Integer(row["pod_number"], exception: false) }.sort
      errors << "Record one result for each seated pod." if result_pods != expected_pods

      seat_player_ids = game_night.game_night_pod_seats.group_by(&:pod_number).transform_values do |seats|
        seats.map(&:player_id)
      end

      results.each do |row|
        pod_number = Integer(row["pod_number"], exception: false)
        draw = draw?(row)
        winner_id = winner_player_id(row)

        errors << "Pod #{pod_number} needs a winner or a draw." if !draw && winner_id.blank?
        errors << "Pod #{pod_number} cannot have both a winner and a draw." if draw && winner_id.present?
        errors << "Pod #{pod_number} winner must be seated in that pod." if winner_id.present? && !seat_player_ids.fetch(pod_number, []).include?(winner_id)

        if row["turns"].present? && !positive_integer?(row["turns"])
          errors << "Pod #{pod_number} turns must be a positive whole number."
        end
      end
    end

    def winner_player_id(row)
      optional_integer(row["winner_player_id"])
    end

    def draw?(row)
      ActiveModel::Type::Boolean.new.cast(row["draw"]) || false
    end

    def optional_integer(value)
      return nil if value.blank?

      Integer(value, exception: false)
    end

    def positive_integer?(value)
      optional_integer(value).to_i.positive?
    end
  end
end
