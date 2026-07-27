# frozen_string_literal: true

class CreateNpnCritiqueOutreachExclusions < ActiveRecord::Migration[8.0]
  def change
    create_table :npn_critique_outreach_exclusions do |t|
      t.integer :user_id, null: false
      t.integer :staff_user_id, null: false
      t.text :reason, null: false
      # NULL means indefinite — "we're done, leave them be".
      t.datetime :expires_at
      t.timestamps
    end

    add_index :npn_critique_outreach_exclusions, :user_id, unique: true
    add_index :npn_critique_outreach_exclusions, :expires_at
  end
end
