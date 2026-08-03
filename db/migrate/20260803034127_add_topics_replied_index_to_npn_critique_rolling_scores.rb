# frozen_string_literal: true

# The public give-and-take count is built by scanning for members at or above
# the chip floor. Covering index so that read is an index-only scan instead of
# a sequential one over every scored member.
class AddTopicsRepliedIndexToNpnCritiqueRollingScores < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # Named explicitly: the default for these two columns overruns Postgres's
  # 63-character limit, and the hash Rails falls back to says nothing.
  INDEX_NAME = "index_npn_critique_scores_on_replied_and_user"

  def change
    remove_index :npn_critique_rolling_scores,
                 %i[topics_replied user_id],
                 name: INDEX_NAME,
                 algorithm: :concurrently,
                 if_exists: true
    add_index :npn_critique_rolling_scores,
              %i[topics_replied user_id],
              name: INDEX_NAME,
              algorithm: :concurrently
  end
end
