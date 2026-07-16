# frozen_string_literal: true

# The model can be autoloaded (e.g. during migrations) before plugin.rb's
# after_initialize requires run, and lib/ is not on the autoload path.
require_relative "../../../lib/discourse_npn_critique_engagement/has_tier"

module DiscourseNpnCritiqueEngagement
  # A member's current standing over the trailing scoring window
  # (npn_critique_window_days), recomputed nightly. One row per member;
  # nothing ever resets — contributions simply age out of the window.
  class Score < ActiveRecord::Base
    self.table_name = "npn_critique_rolling_scores"

    include HasTier

    belongs_to :user

    def self.current_for(user)
      find_by(user_id: user.id)
    end

    def nudge_worthy?
      return false if new_member?
      return false if created_topics == 0
      ratio < SiteSetting.npn_critique_nudge_ratio
    end
  end
end

# == Schema Information
#
# Table name: npn_critique_rolling_scores
#
#  id               :bigint           not null, primary key
#  awards_received  :integer          default(0), not null
#  computed_at      :datetime         not null
#  created_topics   :integer          default(0), not null
#  ratio            :float            default(0.0), not null
#  score            :float            default(0.0), not null
#  tier             :integer          default("new_member"), not null
#  topics_replied   :integer          default(0), not null
#  weighted_replies :float            default(0.0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :integer          not null
#
# Indexes
#
#  index_npn_critique_rolling_scores_on_score    (score)
#  index_npn_critique_rolling_scores_on_user_id  (user_id) UNIQUE
#
