class AddCommanderRulesStorageToLegalitySnapshots < ActiveRecord::Migration[8.1]
  def change
    change_table :legality_snapshots, bulk: true do |t|
      t.string :banned_normalized_names, array: true, null: false, default: []
      t.string :restricted_normalized_names, array: true, null: false, default: []
      t.jsonb :category_bans, null: false, default: []
      t.jsonb :rules_snapshot, null: false, default: {}
      t.date :source_checked_on
    end

    add_index :legality_snapshots, :banned_normalized_names, using: :gin
    add_index :legality_snapshots, :restricted_normalized_names, using: :gin
    add_index :legality_snapshots, :category_bans, using: :gin
  end
end
