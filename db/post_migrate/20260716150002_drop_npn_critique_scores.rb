# frozen_string_literal: true

class DropNpnCritiqueScores < ActiveRecord::Migration[8.0]
  # The per-month scores table is fully unused once the rolling-score tables
  # exist: its rows were nightly recomputations, so nothing needs migrating.
  def up
    drop_table :npn_critique_scores, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
