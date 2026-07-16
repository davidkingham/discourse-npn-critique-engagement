# frozen_string_literal: true

class CreateNpnCritiqueRollingTables < ActiveRecord::Migration[8.0]
  def change
    # One row per member: their standing over the trailing scoring window,
    # recomputed nightly. Replaces the per-month npn_critique_scores table
    # (dropped post-deploy).
    create_table :npn_critique_rolling_scores do |t|
      t.integer :user_id, null: false
      t.float :score, null: false, default: 0.0
      t.integer :tier, null: false, default: 0
      t.integer :created_topics, null: false, default: 0
      t.integer :topics_replied, null: false, default: 0
      t.float :weighted_replies, null: false, default: 0.0
      t.float :ratio, null: false, default: 0.0
      t.datetime :computed_at, null: false
      t.timestamps
    end

    add_index :npn_critique_rolling_scores, :user_id, unique: true
    add_index :npn_critique_rolling_scores, :score

    # Month-end bookkeeping copies of the rolling standing: the record badges,
    # trends, history graphs, and the health dashboard are built from.
    create_table :npn_critique_monthly_snapshots do |t|
      t.integer :user_id, null: false
      t.date :snapshot_month, null: false
      t.float :score, null: false, default: 0.0
      t.integer :tier, null: false, default: 0
      t.integer :created_topics, null: false, default: 0
      t.integer :topics_replied, null: false, default: 0
      t.float :weighted_replies, null: false, default: 0.0
      t.float :ratio, null: false, default: 0.0
      t.datetime :computed_at, null: false
      t.timestamps
    end

    add_index :npn_critique_monthly_snapshots, %i[user_id snapshot_month], unique: true
    add_index :npn_critique_monthly_snapshots, %i[snapshot_month score]
  end
end
