module GameNights
  class PodSeater
    Result = Struct.new(:success, :errors, keyword_init: true) do
      alias_method :success?, :success
    end

    def self.call(game_night, assignments:)
      new(game_night, assignments: assignments).call
    end

    def initialize(game_night, assignments:)
      @game_night = game_night
      @assignments = normalize_assignments(assignments)
      @errors = []
    end

    def call
      validate_assignments
      return Result.new(success: false, errors: errors) if errors.any?

      GameNight.transaction do
        game_night.game_night_pod_results.destroy_all
        game_night.game_night_pod_seats.destroy_all

        assignments.each do |row|
          night_deck = deck_by_player_id.fetch(row.fetch("player_id").to_i)
          game_night.game_night_pod_seats.create!(
            player_id: night_deck.player_id,
            deck: night_deck.deck,
            pod_number: row.fetch("pod_number").to_i,
            seat_number: row.fetch("seat_number").to_i
          )
        end

        game_night.update!(status: "seated")
      end

      Result.new(success: true, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, errors: [ e.message ])
    end

    private

    attr_reader :game_night, :assignments, :errors

    def normalize_assignments(value)
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

    def validate_assignments
      if assignments.empty?
        errors << "Seat at least two players before saving pods."
        return
      end

      checked_player_ids = game_night.game_night_decks.pluck(:player_id).sort
      assigned_player_ids = assignments.filter_map { |row| integer_value(row["player_id"]) }.sort

      if assigned_player_ids != checked_player_ids
        errors << "Seat every checked-in player exactly once."
      end

      assignments.each_with_index do |row, index|
        row_number = index + 1
        errors << "Row #{row_number} needs a pod number." unless positive_integer?(row["pod_number"])
        errors << "Row #{row_number} needs a seat number." unless positive_integer?(row["seat_number"])
      end

      seat_keys = assignments.map { |row| [ row["pod_number"].to_s, row["seat_number"].to_s ] }
      errors << "Each pod seat can only be used once." if seat_keys.uniq.size != seat_keys.size

      pod_counts = assignments.group_by { |row| row["pod_number"].to_i }.transform_values(&:size)
      if pod_counts.values.any? { |count| count < 2 || count > SeatingSuggester::MAX_POD_SIZE }
        errors << "Pods must have two to four players."
      end
    end

    def deck_by_player_id
      @deck_by_player_id ||= game_night.game_night_decks.includes(:deck).index_by(&:player_id)
    end

    def positive_integer?(value)
      integer_value(value).to_i.positive?
    end

    def integer_value(value)
      Integer(value, exception: false)
    end
  end
end
