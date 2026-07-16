# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  class Score < ActiveRecord::Base
    self.table_name = "npn_critique_scores"

    # Ordered worst-to-best so tier comparisons read naturally; new_member
    # sits first because it is "no judgement yet", not a rank.
    enum :tier,
         {
           new_member: 0,
           low_activity: 1,
           priority_outreach: 2,
           watch: 3,
           healthy: 4,
           excellent: 5,
         }

    belongs_to :user

    scope :for_period, ->(period_start) { where(period_start: period_start) }
    scope :finalized, -> { where(finalized: true) }

    # Tiers that may appear on public surfaces (leaderboard medals). Negative
    # signals never leave staff view, so anything below healthy renders as
    # no medal at all.
    PUBLIC_TIERS = %w[healthy excellent].freeze

    def self.current_period_start
      Time.zone.today.beginning_of_month
    end

    def self.current_for(user)
      find_by(user_id: user.id, period_start: current_period_start)
    end

    def public_tier
      tier if PUBLIC_TIERS.include?(tier)
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
# Table name: npn_critique_scores
#
#  id               :bigint           not null, primary key
#  computed_at      :datetime         not null
#  created_topics   :integer          default(0), not null
#  finalized        :boolean          default(FALSE), not null
#  period_start     :date             not null
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
#  index_npn_critique_scores_on_period_start_and_score    (period_start,score)
#  index_npn_critique_scores_on_user_id_and_period_start  (user_id,period_start) UNIQUE
#
