class CreateCardCorpusRefreshes < ActiveRecord::Migration[8.1]
  def change
    create_table :card_corpus_refreshes do |t|
      t.string :source, null: false, default: "scryfall"
      t.string :bulk_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :source_uri, null: false
      t.string :content_type
      t.bigint :content_length
      t.string :etag
      t.string :last_modified
      t.datetime :fetched_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.datetime :scryfall_updated_at
      t.integer :object_count, null: false, default: 0
      t.integer :card_set_count, null: false, default: 0
      t.integer :oracle_card_count, null: false, default: 0
      t.integer :card_printing_count, null: false, default: 0
      t.string :error_code
      t.text :error_message
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps

      t.index [ :source, :bulk_type, :status ]
      t.index [ :source, :bulk_type, :scryfall_updated_at ],
        name: "idx_card_corpus_refresh_source_snapshot"
      t.index :scryfall_updated_at
    end
  end
end
