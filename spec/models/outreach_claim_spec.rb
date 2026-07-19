# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::OutreachClaim do
  fab!(:moderator)
  fab!(:other_moderator, :moderator)
  fab!(:member, :user)
  fab!(:other_member, :user)

  before { SiteSetting.npn_critique_engagement_enabled = true }

  def send_pm(from, to, title: "Checking in on your critiques")
    PostCreator.create!(
      from,
      title: title,
      raw: "Hello there — wanted to say welcome and thanks for sharing your work.",
      archetype: Archetype.private_message,
      target_usernames: [to.username],
    )
  end

  describe "completing a claim from a PM" do
    before { described_class.create!(user_id: member.id, staff_user_id: moderator.id) }

    it "clears the claim and logs the contact when the claimer PMs the member" do
      send_pm(moderator, member)

      expect(described_class.exists?(user_id: member.id)).to eq(false)
      log = DiscourseNpnCritiqueEngagement::OutreachLog.find_by(user_id: member.id)
      expect(log.staff_user_id).to eq(moderator.id)
      expect(log.note).to include("Checking in on your critiques")
    end

    it "ignores PMs from other staff and PMs to other members" do
      send_pm(other_moderator, member)
      send_pm(moderator, other_member)

      expect(described_class.exists?(user_id: member.id)).to eq(true)
      expect(DiscourseNpnCritiqueEngagement::OutreachLog.exists?(user_id: member.id)).to eq(false)
    end

    it "ignores public topics from the claimer" do
      PostCreator.create!(
        moderator,
        title: "A public topic about critiques",
        raw: "Nothing to do with the claim at all.",
        category: Fabricate(:category).id,
      )

      expect(described_class.exists?(user_id: member.id)).to eq(true)
    end

    it "does not complete an expired claim" do
      described_class.where(user_id: member.id).update_all(
        created_at: (described_class.expiry_days + 1).days.ago,
      )

      send_pm(moderator, member)

      expect(described_class.exists?(user_id: member.id)).to eq(true)
      expect(DiscourseNpnCritiqueEngagement::OutreachLog.exists?(user_id: member.id)).to eq(false)
    end
  end
end
