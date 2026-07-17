# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # An editors' pick inside its undo window: staged, visible only to staff,
  # and cancellable without a trace. A delayed job finalizes it — tag, public
  # note, badge, congratulations PM — once the window closes; the nightly job
  # sweeps up any pick whose delayed job was lost.
  class PendingPick < ActiveRecord::Base
    self.table_name = "npn_critique_pending_picks"

    belongs_to :topic
    belongs_to :user

    scope :due, -> { where(finalize_at: ..Time.zone.now) }

    def self.for_topics(topic_ids)
      where(topic_id: topic_ids).includes(:user).index_by(&:topic_id)
    end
  end
end

# == Schema Information
#
# Table name: npn_critique_pending_picks
#
#  id          :bigint           not null, primary key
#  finalize_at :datetime         not null
#  genre       :string
#  reason      :string(1000)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  topic_id    :integer          not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_npn_critique_pending_picks_on_topic_id  (topic_id) UNIQUE
#
