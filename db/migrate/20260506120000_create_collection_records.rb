class CreateCollectionRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :collection_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :source_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :original_filename
      t.integer :imported_count, null: false, default: 0
      t.integer :unresolved_count, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :collection_imports, [ :user_id, :created_at ]
    add_index :collection_imports, :status

    create_table :collection_cards do |t|
      t.references :user, null: false, foreign_key: true
      t.references :oracle_card, foreign_key: true
      t.references :card_printing, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.integer :quantity, null: false, default: 1
      t.string :source_type, null: false, default: "manual"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :collection_cards, [ :user_id, :normalized_name ], unique: true
    add_index :collection_cards, :normalized_name

    create_table :unresolved_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :collection_import, null: false, foreign_key: true
      t.string :status, null: false, default: "open"
      t.string :name
      t.string :normalized_name
      t.integer :quantity, null: false, default: 1
      t.string :reason, null: false
      t.text :raw_line, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :unresolved_entries, [ :user_id, :status ]
    add_index :unresolved_entries, :normalized_name
  end
end
