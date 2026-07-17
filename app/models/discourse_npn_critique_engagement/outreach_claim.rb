# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # "I'll reach out" — a moderator claiming an outreach so two mods don't
  # write the same member at once. Cleared when a contact note is logged;
  # the claimer gets one reminder PM if the contact hasn't been logged, and
  # stale claims expire so a forgotten one can't block a member forever.
  class OutreachClaim < ActiveRecord::Base
    self.table_name = "npn_critique_outreach_claims"

    belongs_to :user
    belongs_to :staff_user, class_name: "User"

    scope :active, -> { where("created_at >= ?", expiry_days.days.ago) }

    def self.expiry_days
      SiteSetting.npn_critique_claim_expiry_days
    end

    def self.active_for(user_ids)
      active.where(user_id: user_ids).includes(:staff_user).index_by(&:user_id)
    end

    # One friendly PM to the claimer once the claim outlives the reminder
    # window without a logged contact. Runs from the nightly job.
    def self.send_reminders
      reminder_hours = SiteSetting.npn_critique_claim_reminder_hours
      return if reminder_hours == 0

      active
        .where(reminded_at: nil)
        .where("created_at <= ?", reminder_hours.hours.ago)
        .includes(:user, :staff_user)
        .find_each do |claim|
          next if claim.user.nil? || claim.staff_user.nil?

          begin
            SystemMessage.create_from_system_user(
              claim.staff_user,
              :npn_outreach_claim_reminder,
              member_username: claim.user.username,
            )
            claim.update!(reminded_at: Time.zone.now)
          rescue => e
            Rails.logger.warn(
              "NPN critique engagement: claim reminder failed for claim #{claim.id}: #{e.message}",
            )
          end
        end
    end

    def active?
      created_at >= self.class.expiry_days.days.ago
    end
  end
end

# == Schema Information
#
# Table name: npn_critique_outreach_claims
#
#  id            :bigint           not null, primary key
#  reminded_at   :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  staff_user_id :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_npn_critique_outreach_claims_on_user_id  (user_id) UNIQUE
#
