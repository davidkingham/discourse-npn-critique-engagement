# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # "Leave them be" — a member a moderator has decided to stop surfacing as
  # outreach work. Some members have been contacted for years and are not
  # going to change; without this they sit at the top of the queue forever and
  # every moderator rediscovers them.
  #
  # The exclusion is deliberately narrow: the member is still scored, still
  # ranked, still badged, still counted in the community's numbers. All that
  # changes is whether they appear on a moderator's to-do list. The reason is
  # required because the moderator reading the queue two years from now needs
  # to know why someone isn't in it.
  class OutreachExclusion < ActiveRecord::Base
    self.table_name = "npn_critique_outreach_exclusions"

    REASON_MAX_LENGTH = 1000

    belongs_to :user
    belongs_to :staff_user, class_name: "User"

    validates :reason, presence: true, length: { maximum: REASON_MAX_LENGTH }

    # An expiry lets the same mechanism cover "not for six months" without a
    # second feature; NULL means indefinite.
    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.zone.now) }

    def self.active_for(user_ids)
      active.where(user_id: user_ids).includes(:staff_user).index_by(&:user_id)
    end

    # The ids to subtract from the queues. A subquery rather than an array so
    # the caller can chain it into the Score scope.
    def self.active_user_ids
      active.select(:user_id)
    end

    def active?
      expires_at.nil? || expires_at > Time.zone.now
    end
  end
end

# == Schema Information
#
# Table name: npn_critique_outreach_exclusions
#
#  id            :bigint           not null, primary key
#  expires_at    :datetime
#  reason        :text             not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  staff_user_id :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_npn_critique_outreach_exclusions_on_expires_at  (expires_at)
#  index_npn_critique_outreach_exclusions_on_user_id     (user_id) UNIQUE
#
