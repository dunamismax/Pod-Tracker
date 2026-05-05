class AddBracketToScorecards < ActiveRecord::Migration[8.1]
  def change
    add_column :scorecards, :bracket, :integer
    add_column :scorecards, :bracket_sub_band, :string
    add_column :scorecards, :bracket_payload, :jsonb, default: {}, null: false

    add_index :scorecards, :bracket
  end
end
