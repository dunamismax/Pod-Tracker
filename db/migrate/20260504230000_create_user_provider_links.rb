class CreateUserProviderLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :user_provider_links do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :handle, null: false
      t.string :normalized_handle, null: false
      t.string :profile_url, null: false
      t.string :label
      t.text :notes

      t.timestamps
    end

    add_index :user_provider_links, [ :user_id, :provider, :normalized_handle ],
      unique: true,
      name: "idx_user_provider_links_on_user_provider_handle"
    add_index :user_provider_links, :provider
  end
end
