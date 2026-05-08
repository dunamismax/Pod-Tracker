class CreateGameNightInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :game_night_invitations do |t|
      t.references :game_night, null: false, foreign_key: true
      t.string :email_address, null: false
      t.string :display_name
      t.references :invited_user, foreign_key: { to_table: :users }
      t.references :responded_user, foreign_key: { to_table: :users }
      t.references :player, foreign_key: true
      t.references :deck, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :token, null: false
      t.text :message
      t.text :response_note
      t.integer :position, null: false
      t.datetime :invited_at, null: false
      t.datetime :reminded_at
      t.datetime :responded_at

      t.timestamps

      t.index [ :game_night_id, :email_address ], unique: true,
              name: "idx_gn_invitations_on_game_night_and_email"
      t.index [ :game_night_id, :position ], unique: true,
              name: "idx_gn_invitations_on_game_night_and_position"
      t.index :token, unique: true
      t.index :status
    end
  end
end
