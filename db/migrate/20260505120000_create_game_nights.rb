class CreateGameNights < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.text :notes
      t.datetime :archived_at

      t.timestamps

      t.index [ :user_id, :normalized_name ], unique: true
    end

    create_table :game_nights do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.date :played_on, null: false
      t.string :location
      t.text :notes
      t.string :status, default: "draft", null: false

      t.timestamps

      t.index [ :user_id, :played_on ]
      t.index [ :user_id, :updated_at ]
      t.index :status
    end

    create_table :game_night_players do |t|
      t.references :game_night, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :notes

      t.timestamps

      t.index [ :game_night_id, :player_id ], unique: true
      t.index [ :game_night_id, :position ], unique: true
    end

    create_table :game_night_decks do |t|
      t.references :game_night, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.references :deck, null: false, foreign_key: true
      t.string :deck_name_snapshot, null: false
      t.string :commander_names_snapshot, default: [], null: false, array: true
      t.integer :position, null: false
      t.text :notes

      t.timestamps

      t.index [ :game_night_id, :player_id ], unique: true
      t.index [ :game_night_id, :deck_id ]
      t.index [ :game_night_id, :position ], unique: true
    end
  end
end
