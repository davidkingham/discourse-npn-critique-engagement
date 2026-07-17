# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # "I'll reach out" — a moderator claiming an outreach so two mods don't
  # write the same member at once. Cleared when a contact note is logged;
  # stale claims expire so a forgotten one can't block a member forever.
  class OutreachClaim < ActiveRecord::Base
    self.table_name = "npn_critique_outreach_claims"

    EXPIRY_DAYS = 7

    belongs_to :user
    belongs_to :staff_user, class_name: "User"

    scope :active, -> { where("created_at >= ?", EXPIRY_DAYS.days.ago) }

    def self.active_for(user_ids)
      active.where(user_id: user_ids).includes(:staff_user).index_by(&:user_id)
    end

    def active?
      created_at >= EXPIRY_DAYS.days.ago
    end
  end
end

# == Schema Information
#
# Table name: npn_critique_outreach_claims
#
#  id            :bigint           not null, primary key
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  staff_user_id :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_npn_critique_outreach_claims_on_user_id  (user_id) UNIQUE
#
