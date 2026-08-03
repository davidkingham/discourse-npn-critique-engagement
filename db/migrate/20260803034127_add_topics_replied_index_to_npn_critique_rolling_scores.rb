# frozen_string_literal: true

# The public give-and-take count is built by scanning for members at or above
# the chip floor. Covering index so that read is an index-only scan instead of
# a sequential one over every scored member.
class AddTopicsRepliedIndexToNpnCritiqueRollingScores < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    remove_index :npn_critique_rolling_scores,
                 %i[topics_replied user_id],
                 algorithm: :concurrently,
                 if_exists: true
    add_index :npn_critique_rolling_scores, %i[topics_replied user_id], algorithm: :concurrently
  end
end
