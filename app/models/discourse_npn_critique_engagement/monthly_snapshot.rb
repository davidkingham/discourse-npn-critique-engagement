# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # A month-end bookkeeping copy of a member's rolling standing, recorded on
  # the 1st. Badges, trends, history graphs, and the health dashboard read
  # from these; the live score itself never resets.
  class MonthlySnapshot < ActiveRecord::Base
    self.table_name = "npn_critique_monthly_snapshots"

    include HasTier

    belongs_to :user

    scope :for_month, ->(month) { where(snapshot_month: month) }

    def self.latest_month
      maximum(:snapshot_month)
    end
  end
end

# == Schema Information
#
# Table name: npn_critique_monthly_snapshots
#
#  id               :bigint           not null, primary key
#  computed_at      :datetime         not null
#  created_topics   :integer          default(0), not null
#  ratio            :float            default(0.0), not null
#  score            :float            default(0.0), not null
#  snapshot_month   :date             not null
#  tier             :integer          default("new_member"), not null
#  topics_replied   :integer          default(0), not null
#  weighted_replies :float            default(0.0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :integer          not null
#
# Indexes
#
#  idx_on_snapshot_month_score_3a1d70bc37    (snapshot_month,score)
#  idx_on_user_id_snapshot_month_ec7dab428a  (user_id,snapshot_month) UNIQUE
#
