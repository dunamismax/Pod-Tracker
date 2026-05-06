class CreateMatchupNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :matchup_notes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :deck, null: false, foreign_key: true
      t.references :commander, foreign_key: true
      t.references :opponent, foreign_key: { to_table: :players }
      t.references :pod, foreign_key: true
      t.references :game_night, foreign_key: true
      t.integer :game_night_pod_number
      t.string :tags, array: true, null: false, default: []
      t.text :body, null: false
      t.datetime :happened_at, null: false

      t.timestamps

      t.index [ :user_id, :happened_at ]
      t.index [ :user_id, :deck_id ]
      t.index [ :user_id, :commander_id ]
      t.index [ :user_id, :opponent_id ]
      t.index [ :user_id, :game_night_id ]
      t.index :tags, using: :gin
    end
  end
end
