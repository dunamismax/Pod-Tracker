class AddProfileAndVerificationToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users do |t|
      t.string :display_name
      t.string :timezone, null: false, default: "UTC"
      t.string :preferred_units, null: false, default: "imperial"
      t.datetime :email_verified_at
      t.datetime :email_verification_sent_at
    end
  end
end
