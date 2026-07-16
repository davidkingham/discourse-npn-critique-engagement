# frozen_string_literal: true

class CreateNpnCritiqueScores < ActiveRecord::Migration[8.0]
  def change
    create_table :npn_critique_scores do |t|
      t.integer :user_id, null: false
      t.date :period_start, null: false
      t.float :score, null: false, default: 0.0
      t.integer :tier, null: false, default: 0
      t.integer :created_topics, null: false, default: 0
      t.integer :topics_replied, null: false, default: 0
      t.float :weighted_replies, null: false, default: 0.0
      t.float :ratio, null: false, default: 0.0
      t.boolean :finalized, null: false, default: false
      t.datetime :computed_at, null: false
      t.timestamps
    end

    add_index :npn_critique_scores, %i[user_id period_start], unique: true
    add_index :npn_critique_scores, %i[period_start score]
  end
end
