class AddShareTokenToDecks < ActiveRecord::Migration[8.1]
  def change
    add_column :decks, :share_token, :string
    add_column :decks, :shared_at, :datetime
    add_column :decks, :share_revoked_at, :datetime

    add_index :decks, :share_token, unique: true, where: "share_token IS NOT NULL"
  end
end
