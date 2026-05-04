class CreateDomainFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :card_sets do |t|
      t.uuid :scryfall_id
      t.string :code, null: false
      t.string :mtgo_code
      t.string :arena_code
      t.integer :tcgplayer_id
      t.string :name, null: false
      t.string :set_type
      t.date :released_on
      t.integer :card_count
      t.boolean :digital, null: false, default: false
      t.boolean :foil_only, null: false, default: false
      t.boolean :nonfoil_only, null: false, default: false
      t.string :icon_svg_uri
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps

      t.index :code, unique: true
      t.index :scryfall_id, unique: true
      t.index :set_type
    end

    create_table :oracle_cards do |t|
      t.uuid :scryfall_oracle_id, null: false
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.string :layout
      t.string :mana_cost
      t.decimal :mana_value, precision: 5, scale: 2
      t.string :type_line
      t.text :oracle_text
      t.string :colors, array: true, null: false, default: []
      t.string :color_identity, array: true, null: false, default: []
      t.string :produced_mana, array: true, null: false, default: []
      t.string :keywords, array: true, null: false, default: []
      t.jsonb :legalities, null: false, default: {}
      t.jsonb :faces, null: false, default: []
      t.jsonb :raw_payload, null: false, default: {}
      t.boolean :reserved, null: false, default: false
      t.integer :edhrec_rank

      t.timestamps

      t.index :scryfall_oracle_id, unique: true
      t.index :name
      t.index :normalized_name
      t.index :color_identity, using: :gin
      t.index :legalities, using: :gin
    end

    create_table :card_printings do |t|
      t.references :oracle_card, null: false, foreign_key: true
      t.references :card_set, null: false, foreign_key: true
      t.uuid :scryfall_id, null: false
      t.string :lang, null: false, default: "en"
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.string :collector_number, null: false
      t.string :rarity
      t.date :released_on
      t.string :image_status
      t.jsonb :image_uris, null: false, default: {}
      t.jsonb :prices, null: false, default: {}
      t.jsonb :purchase_uris, null: false, default: {}
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps

      t.index :scryfall_id, unique: true
      t.index :name
      t.index :normalized_name
      t.index [ :card_set_id, :collector_number ], unique: true
      t.index [ :oracle_card_id, :released_on ]
    end

    create_table :rulings do |t|
      t.references :oracle_card, foreign_key: true
      t.references :card_printing, foreign_key: true
      t.string :source, null: false
      t.string :source_id, null: false
      t.date :published_on
      t.text :comment, null: false
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps

      t.index [ :source, :source_id ], unique: true
      t.index [ :oracle_card_id, :published_on ]
      t.index [ :card_printing_id, :published_on ]
    end

    create_table :legality_snapshots do |t|
      t.string :source, null: false
      t.string :format, null: false, default: "commander"
      t.date :effective_on, null: false
      t.datetime :fetched_at, null: false
      t.string :source_url
      t.string :banned_names, array: true, null: false, default: []
      t.string :restricted_names, array: true, null: false, default: []
      t.jsonb :raw_payload, null: false, default: {}
      t.text :notes

      t.timestamps

      t.index [ :source, :format, :effective_on ], unique: true
      t.index :banned_names, using: :gin
      t.index :restricted_names, using: :gin
    end

    create_table :decks do |t|
      t.references :user, foreign_key: true
      t.string :name, null: false
      t.string :format, null: false, default: "commander"
      t.string :visibility, null: false, default: "private"
      t.string :status, null: false, default: "draft"
      t.string :source_type
      t.string :color_identity, array: true, null: false, default: []
      t.string :commander_names, array: true, null: false, default: []
      t.text :description
      t.datetime :last_imported_at
      t.jsonb :import_metadata, null: false, default: {}

      t.timestamps

      t.index [ :user_id, :updated_at ]
      t.index [ :user_id, :name ]
      t.index :format
      t.index :status
      t.index :visibility
      t.index :color_identity, using: :gin
    end

    create_table :deck_cards do |t|
      t.references :deck, null: false, foreign_key: true
      t.references :oracle_card, foreign_key: true
      t.references :card_printing, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.integer :quantity, null: false, default: 1
      t.string :board, null: false, default: "main"
      t.string :category
      t.integer :position
      t.string :raw_line
      t.jsonb :metadata, null: false, default: {}

      t.timestamps

      t.index [ :deck_id, :board, :position ]
      t.index [ :deck_id, :normalized_name, :board ]
      t.index :normalized_name
      t.index :category
    end

    create_table :commanders do |t|
      t.references :deck, null: false, foreign_key: true
      t.references :oracle_card, foreign_key: true
      t.references :card_printing, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.integer :position, null: false, default: 1
      t.string :raw_line

      t.timestamps

      t.index [ :deck_id, :position ], unique: true
      t.index [ :deck_id, :normalized_name ]
      t.index :normalized_name
    end

    create_table :provider_links do |t|
      t.references :deck, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :external_id
      t.string :url, null: false
      t.string :slug
      t.string :sync_status, null: false, default: "pending"
      t.datetime :last_synced_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps

      t.index [ :provider, :external_id ], unique: true, where: "external_id IS NOT NULL"
      t.index [ :provider, :url ], unique: true
      t.index [ :deck_id, :provider ]
      t.index :sync_status
    end

    create_table :analysis_runs do |t|
      t.references :deck, foreign_key: true
      t.references :user, foreign_key: true
      t.string :kind, null: false, default: "deterministic"
      t.string :status, null: false, default: "queued"
      t.string :rubric_version, null: false
      t.string :ai_model
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.decimal :cost_cents, precision: 12, scale: 4
      t.datetime :queued_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.string :error_code
      t.text :error_message
      t.jsonb :feature_vector, null: false, default: {}
      t.jsonb :deterministic_snapshot, null: false, default: {}
      t.jsonb :ai_request_snapshot, null: false, default: {}
      t.jsonb :ai_response_snapshot, null: false, default: {}

      t.timestamps

      t.index [ :deck_id, :created_at ]
      t.index [ :user_id, :created_at ]
      t.index :status
      t.index :kind
      t.index :rubric_version
    end

    create_table :scorecards do |t|
      t.references :analysis_run, null: false, foreign_key: true, index: { unique: true }
      t.integer :power_score
      t.integer :speed_score
      t.integer :interaction_score
      t.integer :consistency_score
      t.integer :pod_fit_score
      t.integer :salt_score
      t.integer :social_friction_score
      t.string :salt_rating
      t.decimal :confidence, precision: 5, scale: 4
      t.jsonb :evidence, null: false, default: {}
      t.jsonb :improvement_suggestions, null: false, default: []
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps

      t.index :salt_rating
    end

    create_table :pod_evaluations do |t|
      t.references :user, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.integer :deck_count, null: false, default: 0
      t.string :rubric_version
      t.jsonb :deck_snapshot, null: false, default: []
      t.jsonb :score_snapshot, null: false, default: {}
      t.jsonb :mismatch_warnings, null: false, default: []
      t.datetime :evaluated_at

      t.timestamps

      t.index [ :user_id, :updated_at ]
      t.index :status
      t.index :rubric_version
    end

    create_table :salt_social_friction_evidences do |t|
      t.references :analysis_run, null: false, foreign_key: true
      t.references :deck_card, foreign_key: true
      t.references :oracle_card, foreign_key: true
      t.references :card_printing, foreign_key: true
      t.string :evidence_type, null: false
      t.string :category, null: false
      t.string :label, null: false
      t.decimal :score_delta, precision: 7, scale: 3
      t.string :severity
      t.text :explanation
      t.jsonb :source_payload, null: false, default: {}

      t.timestamps

      t.index [ :analysis_run_id, :category ]
      t.index [ :analysis_run_id, :evidence_type ]
      t.index [ :oracle_card_id, :category ]
      t.index :severity
    end

    create_table :audit_events do |t|
      t.references :user, foreign_key: true
      t.references :auditable, polymorphic: true
      t.string :event_name, null: false
      t.datetime :occurred_at, null: false
      t.string :ip_address
      t.string :user_agent
      t.jsonb :metadata, null: false, default: {}

      t.timestamps

      t.index [ :event_name, :occurred_at ]
      t.index [ :user_id, :occurred_at ]
    end
  end
end
