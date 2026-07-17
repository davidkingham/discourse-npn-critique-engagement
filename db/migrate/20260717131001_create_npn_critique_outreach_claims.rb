# frozen_string_literal: true

class CreateNpnCritiqueOutreachClaims < ActiveRecord::Migration[8.0]
  def change
    create_table :npn_critique_outreach_claims do |t|
      t.integer :user_id, null: false
      t.integer :staff_user_id, null: false
      t.timestamps
    end

    add_index :npn_critique_outreach_claims, :user_id, unique: true
  end
end
