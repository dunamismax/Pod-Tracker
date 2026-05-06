module Matchups
  class SessionContext
    def self.for_seating(user:, game_night:, seating_rows:, decks_by_player_id:)
      new(user, game_night, seating_rows, decks_by_player_id).call
    end

    def initialize(user, game_night, seating_rows, decks_by_player_id)
      @user = user
      @game_night = game_night
      @seating_rows = seating_rows
      @decks_by_player_id = decks_by_player_id
    end

    def call
      seating_rows.group_by { |row| row["pod_number"].to_i }.transform_values do |rows|
        notes_for(rows)
      end
    end

    private

    attr_reader :user, :game_night, :seating_rows, :decks_by_player_id

    def notes_for(rows)
      deck_ids = []
      commander_ids = []
      player_ids = []

      rows.each do |row|
        player_id = row["player_id"].to_i
        night_deck = decks_by_player_id[player_id]
        next unless night_deck

        player_ids << player_id
        deck_ids << night_deck.deck_id
        commander_ids.concat(night_deck.deck.commanders.pluck(:id))
      end

      scopes = []
      base_scope = user.matchup_notes.where("game_night_id IS NULL OR game_night_id != ?", game_night.id)
      scopes << base_scope.where(deck_id: deck_ids.uniq) if deck_ids.any?
      scopes << base_scope.where(commander_id: commander_ids.uniq) if commander_ids.any?
      scopes << base_scope.where(opponent_id: player_ids.uniq) if player_ids.any?
      return MatchupNote.none unless scopes.any?

      scopes.reduce { |scope, next_scope| scope.or(next_scope) }
            .includes(:deck, :commander, :opponent, :game_night)
            .recent
            .limit(5)
    end
  end
end
