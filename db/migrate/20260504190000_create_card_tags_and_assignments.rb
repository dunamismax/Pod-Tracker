class CreateCardTagsAndAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :card_tags do |t|
      t.string :slug, null: false
      t.string :category, null: false
      t.string :label, null: false
      t.text :description
      t.decimal :salt_weight, precision: 7, scale: 3
      t.decimal :friction_weight, precision: 7, scale: 3
      t.string :default_severity
      t.jsonb :metadata, null: false, default: {}

      t.timestamps

      t.index :slug, unique: true
      t.index :category
    end

    create_table :card_tag_assignments do |t|
      t.references :card_tag, null: false, foreign_key: true
      t.references :oracle_card, foreign_key: true
      t.string :card_name, null: false
      t.string :normalized_card_name, null: false
      t.string :source, null: false, default: "curated"
      t.text :notes
      t.decimal :weight, precision: 7, scale: 3
      t.string :severity
      t.jsonb :metadata, null: false, default: {}

      t.timestamps

      t.index [ :card_tag_id, :normalized_card_name ], unique: true, name: "index_card_tag_assignments_on_tag_and_card"
      t.index :normalized_card_name
      t.index [ :oracle_card_id, :card_tag_id ]
    end
  end
end
