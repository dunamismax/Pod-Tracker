class CreateGameNightPodRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :game_night_pod_seats do |t|
      t.references :game_night, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.references :deck, null: false, foreign_key: true
      t.integer :pod_number, null: false
      t.integer :seat_number, null: false
      t.string :deck_name_snapshot, null: false
      t.string :commander_names_snapshot, default: [], null: false, array: true
      t.references :analysis_run, foreign_key: true
      t.jsonb :analysis_snapshot, default: {}, null: false
      t.text :notes

      t.timestamps

      t.index [ :game_night_id, :pod_number, :seat_number ], unique: true, name: "idx_game_night_pod_seats_on_pod_and_seat"
      t.index [ :game_night_id, :player_id ], unique: true
      t.index [ :game_night_id, :deck_id ]
    end

    create_table :game_night_pod_results do |t|
      t.references :game_night, null: false, foreign_key: true
      t.integer :pod_number, null: false
      t.references :winner_player, foreign_key: { to_table: :players }
      t.boolean :draw, default: false, null: false
      t.integer :turns
      t.string :win_condition
      t.text :notes

      t.timestamps

      t.index [ :game_night_id, :pod_number ], unique: true
    end
  end
end
