# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_07_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "analysis_runs", force: :cascade do |t|
    t.string "ai_model"
    t.jsonb "ai_request_snapshot", default: {}, null: false
    t.jsonb "ai_response_snapshot", default: {}, null: false
    t.jsonb "codex_rate_limit_snapshot", default: {}, null: false
    t.datetime "completed_at"
    t.integer "completion_tokens"
    t.decimal "cost_cents", precision: 12, scale: 4
    t.datetime "created_at", null: false
    t.bigint "deck_id"
    t.jsonb "deterministic_snapshot", default: {}, null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "failed_at"
    t.jsonb "feature_vector", default: {}, null: false
    t.string "kind", default: "deterministic", null: false
    t.integer "latency_ms"
    t.bigint "pod_id"
    t.integer "prompt_tokens"
    t.string "prompt_version"
    t.datetime "queued_at", null: false
    t.string "rubric_version", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["deck_id", "created_at"], name: "index_analysis_runs_on_deck_id_and_created_at"
    t.index ["deck_id"], name: "index_analysis_runs_on_deck_id"
    t.index ["kind"], name: "index_analysis_runs_on_kind"
    t.index ["latency_ms"], name: "index_analysis_runs_on_latency_ms"
    t.index ["pod_id", "created_at"], name: "index_analysis_runs_on_pod_id_and_created_at"
    t.index ["pod_id"], name: "index_analysis_runs_on_pod_id"
    t.index ["prompt_version"], name: "index_analysis_runs_on_prompt_version"
    t.index ["rubric_version"], name: "index_analysis_runs_on_rubric_version"
    t.index ["status"], name: "index_analysis_runs_on_status"
    t.index ["user_id", "created_at"], name: "index_analysis_runs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_analysis_runs_on_user_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_events_on_auditable"
    t.index ["event_name", "occurred_at"], name: "index_audit_events_on_event_name_and_occurred_at"
    t.index ["user_id", "occurred_at"], name: "index_audit_events_on_user_id_and_occurred_at"
    t.index ["user_id"], name: "index_audit_events_on_user_id"
  end

  create_table "card_corpus_refreshes", force: :cascade do |t|
    t.string "bulk_type", null: false
    t.integer "card_printing_count", default: 0, null: false
    t.integer "card_set_count", default: 0, null: false
    t.datetime "completed_at"
    t.bigint "content_length"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.string "etag"
    t.datetime "failed_at"
    t.datetime "fetched_at", null: false
    t.string "last_modified"
    t.integer "object_count", default: 0, null: false
    t.integer "oracle_card_count", default: 0, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "scryfall_updated_at"
    t.string "source", default: "scryfall", null: false
    t.string "source_uri", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["scryfall_updated_at"], name: "index_card_corpus_refreshes_on_scryfall_updated_at"
    t.index ["source", "bulk_type", "scryfall_updated_at"], name: "idx_card_corpus_refresh_source_snapshot"
    t.index ["source", "bulk_type", "status"], name: "index_card_corpus_refreshes_on_source_and_bulk_type_and_status"
  end

  create_table "card_printings", force: :cascade do |t|
    t.bigint "card_set_id", null: false
    t.string "collector_number", null: false
    t.datetime "created_at", null: false
    t.string "image_status"
    t.jsonb "image_uris", default: {}, null: false
    t.string "lang", default: "en", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.bigint "oracle_card_id", null: false
    t.jsonb "prices", default: {}, null: false
    t.jsonb "purchase_uris", default: {}, null: false
    t.string "rarity"
    t.jsonb "raw_payload", default: {}, null: false
    t.date "released_on"
    t.uuid "scryfall_id", null: false
    t.datetime "updated_at", null: false
    t.index ["card_set_id", "collector_number"], name: "index_card_printings_on_card_set_id_and_collector_number", unique: true
    t.index ["card_set_id"], name: "index_card_printings_on_card_set_id"
    t.index ["name"], name: "index_card_printings_on_name"
    t.index ["normalized_name"], name: "index_card_printings_on_normalized_name"
    t.index ["oracle_card_id", "released_on"], name: "index_card_printings_on_oracle_card_id_and_released_on"
    t.index ["oracle_card_id"], name: "index_card_printings_on_oracle_card_id"
    t.index ["scryfall_id"], name: "index_card_printings_on_scryfall_id", unique: true
  end

  create_table "card_sets", force: :cascade do |t|
    t.string "arena_code"
    t.integer "card_count"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.boolean "digital", default: false, null: false
    t.boolean "foil_only", default: false, null: false
    t.string "icon_svg_uri"
    t.string "mtgo_code"
    t.string "name", null: false
    t.boolean "nonfoil_only", default: false, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.date "released_on"
    t.uuid "scryfall_id"
    t.string "set_type"
    t.integer "tcgplayer_id"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_card_sets_on_code", unique: true
    t.index ["scryfall_id"], name: "index_card_sets_on_scryfall_id", unique: true
    t.index ["set_type"], name: "index_card_sets_on_set_type"
  end

  create_table "card_tag_assignments", force: :cascade do |t|
    t.string "card_name", null: false
    t.bigint "card_tag_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "normalized_card_name", null: false
    t.text "notes"
    t.bigint "oracle_card_id"
    t.string "severity"
    t.string "source", default: "curated", null: false
    t.datetime "updated_at", null: false
    t.decimal "weight", precision: 7, scale: 3
    t.index ["card_tag_id", "normalized_card_name"], name: "index_card_tag_assignments_on_tag_and_card", unique: true
    t.index ["card_tag_id"], name: "index_card_tag_assignments_on_card_tag_id"
    t.index ["normalized_card_name"], name: "index_card_tag_assignments_on_normalized_card_name"
    t.index ["oracle_card_id", "card_tag_id"], name: "index_card_tag_assignments_on_oracle_card_id_and_card_tag_id"
    t.index ["oracle_card_id"], name: "index_card_tag_assignments_on_oracle_card_id"
  end

  create_table "card_tags", force: :cascade do |t|
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.string "default_severity"
    t.text "description"
    t.decimal "friction_weight", precision: 7, scale: 3
    t.string "label", null: false
    t.jsonb "metadata", default: {}, null: false
    t.decimal "salt_weight", precision: 7, scale: 3
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_card_tags_on_category"
    t.index ["slug"], name: "index_card_tags_on_slug", unique: true
  end

  create_table "codex_accounts", force: :cascade do |t|
    t.string "auth_mode", null: false
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.jsonb "credential_metadata", default: {}, null: false
    t.datetime "credentials_expire_at"
    t.datetime "disconnected_at"
    t.string "displayed_email"
    t.text "encrypted_credential_payload"
    t.string "last_error_code"
    t.text "last_error_message"
    t.datetime "last_failed_at"
    t.datetime "last_synced_at"
    t.string "plan_type"
    t.jsonb "rate_limit_snapshot", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["auth_mode"], name: "index_codex_accounts_on_auth_mode"
    t.index ["status"], name: "index_codex_accounts_on_status"
    t.index ["user_id"], name: "index_codex_accounts_on_user_id", unique: true
  end

  create_table "codex_login_attempts", force: :cascade do |t|
    t.string "auth_mode", null: false
    t.datetime "awaiting_user_at"
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "external_handle"
    t.datetime "failed_at"
    t.string "failure_code"
    t.text "failure_message"
    t.datetime "last_polled_at"
    t.string "login_url"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "started_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "user_code"
    t.bigint "user_id", null: false
    t.string "verification_uri"
    t.index ["external_handle"], name: "index_codex_login_attempts_on_external_handle", unique: true, where: "(external_handle IS NOT NULL)"
    t.index ["status"], name: "index_codex_login_attempts_on_status"
    t.index ["user_id", "created_at"], name: "index_codex_login_attempts_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_codex_login_attempts_on_user_id"
  end

  create_table "collection_cards", force: :cascade do |t|
    t.bigint "card_printing_id"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.bigint "oracle_card_id"
    t.integer "quantity", default: 1, null: false
    t.string "source_type", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["card_printing_id"], name: "index_collection_cards_on_card_printing_id"
    t.index ["normalized_name"], name: "index_collection_cards_on_normalized_name"
    t.index ["oracle_card_id"], name: "index_collection_cards_on_oracle_card_id"
    t.index ["user_id", "normalized_name"], name: "index_collection_cards_on_user_id_and_normalized_name", unique: true
    t.index ["user_id"], name: "index_collection_cards_on_user_id"
  end

  create_table "collection_imports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "imported_count", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "original_filename"
    t.string "source_type", null: false
    t.string "status", default: "pending", null: false
    t.integer "unresolved_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status"], name: "index_collection_imports_on_status"
    t.index ["user_id", "created_at"], name: "index_collection_imports_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_collection_imports_on_user_id"
  end

  create_table "commanders", force: :cascade do |t|
    t.bigint "card_printing_id"
    t.datetime "created_at", null: false
    t.bigint "deck_id", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.bigint "oracle_card_id"
    t.integer "position", default: 1, null: false
    t.string "raw_line"
    t.datetime "updated_at", null: false
    t.index ["card_printing_id"], name: "index_commanders_on_card_printing_id"
    t.index ["deck_id", "normalized_name"], name: "index_commanders_on_deck_id_and_normalized_name"
    t.index ["deck_id", "position"], name: "index_commanders_on_deck_id_and_position", unique: true
    t.index ["deck_id"], name: "index_commanders_on_deck_id"
    t.index ["normalized_name"], name: "index_commanders_on_normalized_name"
    t.index ["oracle_card_id"], name: "index_commanders_on_oracle_card_id"
  end

  create_table "deck_cards", force: :cascade do |t|
    t.string "board", default: "main", null: false
    t.bigint "card_printing_id"
    t.string "category"
    t.datetime "created_at", null: false
    t.bigint "deck_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.bigint "oracle_card_id"
    t.integer "position"
    t.integer "quantity", default: 1, null: false
    t.string "raw_line"
    t.datetime "updated_at", null: false
    t.index ["card_printing_id"], name: "index_deck_cards_on_card_printing_id"
    t.index ["category"], name: "index_deck_cards_on_category"
    t.index ["deck_id", "board", "position"], name: "index_deck_cards_on_deck_id_and_board_and_position"
    t.index ["deck_id", "normalized_name", "board"], name: "index_deck_cards_on_deck_id_and_normalized_name_and_board"
    t.index ["deck_id"], name: "index_deck_cards_on_deck_id"
    t.index ["normalized_name"], name: "index_deck_cards_on_normalized_name"
    t.index ["oracle_card_id"], name: "index_deck_cards_on_oracle_card_id"
  end

  create_table "decks", force: :cascade do |t|
    t.string "color_identity", default: [], null: false, array: true
    t.string "commander_names", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.text "description"
    t.string "format", default: "commander", null: false
    t.bigint "guest_for_pod_id"
    t.jsonb "import_metadata", default: {}, null: false
    t.datetime "last_imported_at"
    t.string "name", null: false
    t.string "source_type"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "visibility", default: "private", null: false
    t.index ["color_identity"], name: "index_decks_on_color_identity", using: :gin
    t.index ["format"], name: "index_decks_on_format"
    t.index ["guest_for_pod_id"], name: "index_decks_on_guest_for_pod_id"
    t.index ["status"], name: "index_decks_on_status"
    t.index ["user_id", "name"], name: "index_decks_on_user_id_and_name"
    t.index ["user_id", "updated_at"], name: "index_decks_on_user_id_and_updated_at"
    t.index ["user_id"], name: "index_decks_on_user_id"
    t.index ["visibility"], name: "index_decks_on_visibility"
  end

  create_table "game_night_decks", force: :cascade do |t|
    t.string "commander_names_snapshot", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.bigint "deck_id", null: false
    t.string "deck_name_snapshot", null: false
    t.bigint "game_night_id", null: false
    t.text "notes"
    t.bigint "player_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["deck_id"], name: "index_game_night_decks_on_deck_id"
    t.index ["game_night_id", "deck_id"], name: "index_game_night_decks_on_game_night_id_and_deck_id"
    t.index ["game_night_id", "player_id"], name: "index_game_night_decks_on_game_night_id_and_player_id", unique: true
    t.index ["game_night_id", "position"], name: "index_game_night_decks_on_game_night_id_and_position", unique: true
    t.index ["game_night_id"], name: "index_game_night_decks_on_game_night_id"
    t.index ["player_id"], name: "index_game_night_decks_on_player_id"
  end

  create_table "game_night_players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_night_id", null: false
    t.text "notes"
    t.bigint "player_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["game_night_id", "player_id"], name: "index_game_night_players_on_game_night_id_and_player_id", unique: true
    t.index ["game_night_id", "position"], name: "index_game_night_players_on_game_night_id_and_position", unique: true
    t.index ["game_night_id"], name: "index_game_night_players_on_game_night_id"
    t.index ["player_id"], name: "index_game_night_players_on_player_id"
  end

  create_table "game_night_pod_results", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "draw", default: false, null: false
    t.bigint "game_night_id", null: false
    t.text "notes"
    t.integer "pod_number", null: false
    t.integer "turns"
    t.datetime "updated_at", null: false
    t.string "win_condition"
    t.bigint "winner_player_id"
    t.index ["game_night_id", "pod_number"], name: "index_game_night_pod_results_on_game_night_id_and_pod_number", unique: true
    t.index ["game_night_id"], name: "index_game_night_pod_results_on_game_night_id"
    t.index ["winner_player_id"], name: "index_game_night_pod_results_on_winner_player_id"
  end

  create_table "game_night_pod_seats", force: :cascade do |t|
    t.bigint "analysis_run_id"
    t.jsonb "analysis_snapshot", default: {}, null: false
    t.string "commander_names_snapshot", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.bigint "deck_id", null: false
    t.string "deck_name_snapshot", null: false
    t.bigint "game_night_id", null: false
    t.text "notes"
    t.bigint "player_id", null: false
    t.integer "pod_number", null: false
    t.integer "seat_number", null: false
    t.datetime "updated_at", null: false
    t.index ["analysis_run_id"], name: "index_game_night_pod_seats_on_analysis_run_id"
    t.index ["deck_id"], name: "index_game_night_pod_seats_on_deck_id"
    t.index ["game_night_id", "deck_id"], name: "index_game_night_pod_seats_on_game_night_id_and_deck_id"
    t.index ["game_night_id", "player_id"], name: "index_game_night_pod_seats_on_game_night_id_and_player_id", unique: true
    t.index ["game_night_id", "pod_number", "seat_number"], name: "idx_game_night_pod_seats_on_pod_and_seat", unique: true
    t.index ["game_night_id"], name: "index_game_night_pod_seats_on_game_night_id"
    t.index ["player_id"], name: "index_game_night_pod_seats_on_player_id"
  end

  create_table "game_nights", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "location"
    t.string "name", null: false
    t.text "notes"
    t.date "played_on", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status"], name: "index_game_nights_on_status"
    t.index ["user_id", "played_on"], name: "index_game_nights_on_user_id_and_played_on"
    t.index ["user_id", "updated_at"], name: "index_game_nights_on_user_id_and_updated_at"
    t.index ["user_id"], name: "index_game_nights_on_user_id"
  end

  create_table "legality_snapshots", force: :cascade do |t|
    t.string "banned_names", default: [], null: false, array: true
    t.string "banned_normalized_names", default: [], null: false, array: true
    t.jsonb "category_bans", default: [], null: false
    t.datetime "created_at", null: false
    t.date "effective_on", null: false
    t.datetime "fetched_at", null: false
    t.string "format", default: "commander", null: false
    t.text "notes"
    t.jsonb "raw_payload", default: {}, null: false
    t.string "restricted_names", default: [], null: false, array: true
    t.string "restricted_normalized_names", default: [], null: false, array: true
    t.jsonb "rules_snapshot", default: {}, null: false
    t.string "source", null: false
    t.date "source_checked_on"
    t.string "source_url"
    t.datetime "updated_at", null: false
    t.index ["banned_names"], name: "index_legality_snapshots_on_banned_names", using: :gin
    t.index ["banned_normalized_names"], name: "index_legality_snapshots_on_banned_normalized_names", using: :gin
    t.index ["category_bans"], name: "index_legality_snapshots_on_category_bans", using: :gin
    t.index ["restricted_names"], name: "index_legality_snapshots_on_restricted_names", using: :gin
    t.index ["restricted_normalized_names"], name: "index_legality_snapshots_on_restricted_normalized_names", using: :gin
    t.index ["source", "format", "effective_on"], name: "index_legality_snapshots_on_source_and_format_and_effective_on", unique: true
  end

  create_table "matchup_notes", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "commander_id"
    t.datetime "created_at", null: false
    t.bigint "deck_id", null: false
    t.bigint "game_night_id"
    t.integer "game_night_pod_number"
    t.datetime "happened_at", null: false
    t.bigint "opponent_id"
    t.bigint "pod_id"
    t.string "tags", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["commander_id"], name: "index_matchup_notes_on_commander_id"
    t.index ["deck_id"], name: "index_matchup_notes_on_deck_id"
    t.index ["game_night_id"], name: "index_matchup_notes_on_game_night_id"
    t.index ["opponent_id"], name: "index_matchup_notes_on_opponent_id"
    t.index ["pod_id"], name: "index_matchup_notes_on_pod_id"
    t.index ["tags"], name: "index_matchup_notes_on_tags", using: :gin
    t.index ["user_id", "commander_id"], name: "index_matchup_notes_on_user_id_and_commander_id"
    t.index ["user_id", "deck_id"], name: "index_matchup_notes_on_user_id_and_deck_id"
    t.index ["user_id", "game_night_id"], name: "index_matchup_notes_on_user_id_and_game_night_id"
    t.index ["user_id", "happened_at"], name: "index_matchup_notes_on_user_id_and_happened_at"
    t.index ["user_id", "opponent_id"], name: "index_matchup_notes_on_user_id_and_opponent_id"
    t.index ["user_id"], name: "index_matchup_notes_on_user_id"
  end

  create_table "oracle_cards", force: :cascade do |t|
    t.string "color_identity", default: [], null: false, array: true
    t.string "colors", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.integer "edhrec_rank"
    t.jsonb "faces", default: [], null: false
    t.string "keywords", default: [], null: false, array: true
    t.string "layout"
    t.jsonb "legalities", default: {}, null: false
    t.string "mana_cost"
    t.decimal "mana_value", precision: 5, scale: 2
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.text "oracle_text"
    t.string "produced_mana", default: [], null: false, array: true
    t.jsonb "raw_payload", default: {}, null: false
    t.boolean "reserved", default: false, null: false
    t.uuid "scryfall_oracle_id", null: false
    t.string "type_line"
    t.datetime "updated_at", null: false
    t.index ["color_identity"], name: "index_oracle_cards_on_color_identity", using: :gin
    t.index ["legalities"], name: "index_oracle_cards_on_legalities", using: :gin
    t.index ["name"], name: "index_oracle_cards_on_name"
    t.index ["normalized_name"], name: "index_oracle_cards_on_normalized_name"
    t.index ["scryfall_oracle_id"], name: "index_oracle_cards_on_scryfall_oracle_id", unique: true
  end

  create_table "players", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "normalized_name"], name: "index_players_on_user_id_and_normalized_name", unique: true
    t.index ["user_id"], name: "index_players_on_user_id"
  end

  create_table "pod_analysis_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "failed_at"
    t.bigint "pod_id", null: false
    t.datetime "queued_at", null: false
    t.string "rubric_version", null: false
    t.jsonb "rule_zero_brief", default: {}, null: false
    t.jsonb "snapshot", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.jsonb "suggestions", default: [], null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.jsonb "warnings", default: [], null: false
    t.index ["pod_id", "created_at"], name: "index_pod_analysis_runs_on_pod_id_and_created_at"
    t.index ["pod_id"], name: "index_pod_analysis_runs_on_pod_id"
    t.index ["status"], name: "index_pod_analysis_runs_on_status"
    t.index ["user_id"], name: "index_pod_analysis_runs_on_user_id"
  end

  create_table "pod_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "deck_id", null: false
    t.string "label"
    t.bigint "pod_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["deck_id"], name: "index_pod_slots_on_deck_id"
    t.index ["pod_id", "position"], name: "index_pod_slots_on_pod_id_and_position", unique: true
    t.index ["pod_id"], name: "index_pod_slots_on_pod_id"
  end

  create_table "pods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "format", default: "commander", null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "share_revoked_at"
    t.string "share_token"
    t.datetime "shared_at"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["share_token"], name: "index_pods_on_share_token", unique: true, where: "(share_token IS NOT NULL)"
    t.index ["user_id", "updated_at"], name: "index_pods_on_user_id_and_updated_at"
    t.index ["user_id"], name: "index_pods_on_user_id"
  end

  create_table "provider_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "deck_id", null: false
    t.string "external_id"
    t.datetime "last_synced_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "provider", null: false
    t.string "slug"
    t.string "sync_status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["deck_id", "provider"], name: "index_provider_links_on_deck_id_and_provider"
    t.index ["deck_id"], name: "index_provider_links_on_deck_id"
    t.index ["provider", "external_id"], name: "index_provider_links_on_provider_and_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["provider", "url"], name: "index_provider_links_on_provider_and_url", unique: true
    t.index ["sync_status"], name: "index_provider_links_on_sync_status"
  end

  create_table "rulings", force: :cascade do |t|
    t.bigint "card_printing_id"
    t.text "comment", null: false
    t.datetime "created_at", null: false
    t.bigint "oracle_card_id"
    t.date "published_on"
    t.jsonb "raw_payload", default: {}, null: false
    t.string "source", null: false
    t.string "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["card_printing_id", "published_on"], name: "index_rulings_on_card_printing_id_and_published_on"
    t.index ["card_printing_id"], name: "index_rulings_on_card_printing_id"
    t.index ["oracle_card_id", "published_on"], name: "index_rulings_on_oracle_card_id_and_published_on"
    t.index ["oracle_card_id"], name: "index_rulings_on_oracle_card_id"
    t.index ["source", "source_id"], name: "index_rulings_on_source_and_source_id", unique: true
  end

  create_table "salt_social_friction_evidences", force: :cascade do |t|
    t.bigint "analysis_run_id", null: false
    t.bigint "card_printing_id"
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.bigint "deck_card_id"
    t.string "evidence_type", null: false
    t.text "explanation"
    t.string "label", null: false
    t.bigint "oracle_card_id"
    t.decimal "score_delta", precision: 7, scale: 3
    t.string "severity"
    t.jsonb "source_payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["analysis_run_id", "category"], name: "idx_on_analysis_run_id_category_92cf5668b7"
    t.index ["analysis_run_id", "evidence_type"], name: "idx_on_analysis_run_id_evidence_type_33588339cb"
    t.index ["analysis_run_id"], name: "index_salt_social_friction_evidences_on_analysis_run_id"
    t.index ["card_printing_id"], name: "index_salt_social_friction_evidences_on_card_printing_id"
    t.index ["deck_card_id"], name: "index_salt_social_friction_evidences_on_deck_card_id"
    t.index ["oracle_card_id", "category"], name: "idx_on_oracle_card_id_category_20dfd78ae6"
    t.index ["oracle_card_id"], name: "index_salt_social_friction_evidences_on_oracle_card_id"
    t.index ["severity"], name: "index_salt_social_friction_evidences_on_severity"
  end

  create_table "scorecards", force: :cascade do |t|
    t.bigint "analysis_run_id", null: false
    t.integer "bracket"
    t.jsonb "bracket_payload", default: {}, null: false
    t.string "bracket_sub_band"
    t.decimal "confidence", precision: 5, scale: 4
    t.integer "consistency_score"
    t.datetime "created_at", null: false
    t.jsonb "evidence", default: {}, null: false
    t.jsonb "improvement_suggestions", default: [], null: false
    t.integer "interaction_score"
    t.integer "pod_fit_score"
    t.integer "power_score"
    t.jsonb "raw_payload", default: {}, null: false
    t.string "salt_rating"
    t.integer "salt_score"
    t.integer "social_friction_score"
    t.integer "speed_score"
    t.datetime "updated_at", null: false
    t.index ["analysis_run_id"], name: "index_scorecards_on_analysis_run_id", unique: true
    t.index ["bracket"], name: "index_scorecards_on_bracket"
    t.index ["salt_rating"], name: "index_scorecards_on_salt_rating"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "unresolved_entries", force: :cascade do |t|
    t.bigint "collection_import_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name"
    t.string "normalized_name"
    t.integer "quantity", default: 1, null: false
    t.text "raw_line", null: false
    t.string "reason", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["collection_import_id"], name: "index_unresolved_entries_on_collection_import_id"
    t.index ["normalized_name"], name: "index_unresolved_entries_on_normalized_name"
    t.index ["user_id", "status"], name: "index_unresolved_entries_on_user_id_and_status"
    t.index ["user_id"], name: "index_unresolved_entries_on_user_id"
  end

  create_table "user_provider_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "handle", null: false
    t.string "label"
    t.string "normalized_handle", null: false
    t.text "notes"
    t.string "profile_url", null: false
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider"], name: "index_user_provider_links_on_provider"
    t.index ["user_id", "provider", "normalized_handle"], name: "idx_user_provider_links_on_user_provider_handle", unique: true
    t.index ["user_id"], name: "index_user_provider_links_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address", null: false
    t.datetime "email_verification_sent_at"
    t.datetime "email_verified_at"
    t.string "password_digest", null: false
    t.string "preferred_units", default: "imperial", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "analysis_runs", "decks"
  add_foreign_key "analysis_runs", "pods"
  add_foreign_key "analysis_runs", "users"
  add_foreign_key "audit_events", "users"
  add_foreign_key "card_printings", "card_sets"
  add_foreign_key "card_printings", "oracle_cards"
  add_foreign_key "card_tag_assignments", "card_tags"
  add_foreign_key "card_tag_assignments", "oracle_cards"
  add_foreign_key "codex_accounts", "users"
  add_foreign_key "codex_login_attempts", "users"
  add_foreign_key "collection_cards", "card_printings"
  add_foreign_key "collection_cards", "oracle_cards"
  add_foreign_key "collection_cards", "users"
  add_foreign_key "collection_imports", "users"
  add_foreign_key "commanders", "card_printings"
  add_foreign_key "commanders", "decks"
  add_foreign_key "commanders", "oracle_cards"
  add_foreign_key "deck_cards", "card_printings"
  add_foreign_key "deck_cards", "decks"
  add_foreign_key "deck_cards", "oracle_cards"
  add_foreign_key "decks", "pods", column: "guest_for_pod_id"
  add_foreign_key "decks", "users"
  add_foreign_key "game_night_decks", "decks"
  add_foreign_key "game_night_decks", "game_nights"
  add_foreign_key "game_night_decks", "players"
  add_foreign_key "game_night_players", "game_nights"
  add_foreign_key "game_night_players", "players"
  add_foreign_key "game_night_pod_results", "game_nights"
  add_foreign_key "game_night_pod_results", "players", column: "winner_player_id"
  add_foreign_key "game_night_pod_seats", "analysis_runs"
  add_foreign_key "game_night_pod_seats", "decks"
  add_foreign_key "game_night_pod_seats", "game_nights"
  add_foreign_key "game_night_pod_seats", "players"
  add_foreign_key "game_nights", "users"
  add_foreign_key "matchup_notes", "commanders"
  add_foreign_key "matchup_notes", "decks"
  add_foreign_key "matchup_notes", "game_nights"
  add_foreign_key "matchup_notes", "players", column: "opponent_id"
  add_foreign_key "matchup_notes", "pods"
  add_foreign_key "matchup_notes", "users"
  add_foreign_key "players", "users"
  add_foreign_key "pod_analysis_runs", "pods"
  add_foreign_key "pod_analysis_runs", "users"
  add_foreign_key "pod_slots", "decks"
  add_foreign_key "pod_slots", "pods"
  add_foreign_key "pods", "users"
  add_foreign_key "provider_links", "decks"
  add_foreign_key "rulings", "card_printings"
  add_foreign_key "rulings", "oracle_cards"
  add_foreign_key "salt_social_friction_evidences", "analysis_runs"
  add_foreign_key "salt_social_friction_evidences", "card_printings"
  add_foreign_key "salt_social_friction_evidences", "deck_cards"
  add_foreign_key "salt_social_friction_evidences", "oracle_cards"
  add_foreign_key "scorecards", "analysis_runs"
  add_foreign_key "sessions", "users"
  add_foreign_key "unresolved_entries", "collection_imports"
  add_foreign_key "unresolved_entries", "users"
  add_foreign_key "user_provider_links", "users"
end
