# frozen_string_literal: true

class CreateNpnCritiqueOutreachLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :npn_critique_outreach_logs do |t|
      t.integer :user_id, null: false
      t.integer :staff_user_id, null: false
      t.text :note, null: false
      t.timestamps
    end

    add_index :npn_critique_outreach_logs, %i[user_id created_at]
  end
end
