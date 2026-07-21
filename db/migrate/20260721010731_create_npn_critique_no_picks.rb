# frozen_string_literal: true

class CreateNpnCritiqueNoPicks < ActiveRecord::Migration[8.0]
  def change
    create_table :npn_critique_no_picks do |t|
      t.string :genre, null: false
      t.integer :user_id, null: false
      t.timestamps
    end

    add_index :npn_critique_no_picks, %i[genre created_at]
  end
end
