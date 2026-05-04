class CreateCodexLoginAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_login_attempts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :auth_mode, null: false
      t.string :status, null: false, default: "pending"
      t.string :external_handle
      t.string :login_url
      t.string :verification_uri
      t.string :user_code
      t.datetime :started_at, null: false
      t.datetime :awaiting_user_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.datetime :failed_at
      t.datetime :expires_at
      t.datetime :last_polled_at
      t.string :failure_code
      t.text :failure_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :codex_login_attempts, %i[user_id created_at]
    add_index :codex_login_attempts, :status
    add_index :codex_login_attempts, :external_handle, unique: true, where: "external_handle IS NOT NULL"
  end
end
