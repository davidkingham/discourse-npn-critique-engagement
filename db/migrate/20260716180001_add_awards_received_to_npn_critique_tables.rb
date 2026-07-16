# frozen_string_literal: true

class AddAwardsReceivedToNpnCritiqueTables < ActiveRecord::Migration[8.0]
  def change
    add_column :npn_critique_rolling_scores, :awards_received, :integer, null: false, default: 0
    add_column :npn_critique_monthly_snapshots, :awards_received, :integer, null: false, default: 0
  end
end
