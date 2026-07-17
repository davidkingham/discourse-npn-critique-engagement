# frozen_string_literal: true

class CreateNpnCritiquePendingPicks < ActiveRecord::Migration[8.0]
  def change
    create_table :npn_critique_pending_picks do |t|
      t.integer :topic_id, null: false
      t.integer :user_id, null: false
      t.string :genre
      t.string :reason, limit: 1000
      t.datetime :finalize_at, null: false
      t.timestamps
    end

    add_index :npn_critique_pending_picks, :topic_id, unique: true
  end
end
