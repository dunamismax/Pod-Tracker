class AddGuestForPodToDecks < ActiveRecord::Migration[8.1]
  def change
    add_reference :decks, :guest_for_pod,
                  null: true,
                  foreign_key: { to_table: :pods },
                  index: true
  end
end
