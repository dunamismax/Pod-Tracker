class CreateCodexAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_accounts do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :auth_mode, null: false
      t.string :status, null: false, default: "pending"
      t.string :displayed_email
      t.string :plan_type
      t.text :encrypted_credential_payload
      t.jsonb :credential_metadata, null: false, default: {}
      t.jsonb :rate_limit_snapshot, null: false, default: {}
      t.string :last_error_code
      t.text :last_error_message
      t.datetime :connected_at
      t.datetime :disconnected_at
      t.datetime :last_synced_at
      t.datetime :last_failed_at
      t.datetime :credentials_expire_at

      t.timestamps
    end
    add_index :codex_accounts, :status
    add_index :codex_accounts, :auth_mode
  end
end
