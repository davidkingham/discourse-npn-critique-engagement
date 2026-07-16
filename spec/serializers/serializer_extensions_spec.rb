# frozen_string_literal: true

require "rails_helper"

def create_npn_score(member, attributes = {})
  DiscourseNpnCritiqueEngagement::Score.create!(
    {
      user_id: member.id,
      score: -150,
      tier: :watch,
      created_topics: 6,
      topics_replied: 2,
      ratio: 0.33,
      computed_at: Time.zone.now,
    }.merge(attributes),
  )
end

describe UserCardSerializer do
  fab!(:staff, :moderator)
  fab!(:member) { Fabricate(:user, created_at: 3.months.ago) }

  before { SiteSetting.npn_critique_engagement_enabled = true }

  describe "#npn_critique_engagement" do
    it "is serialized for staff" do
      create_npn_score(member)

      json = described_class.new(member, scope: staff.guardian, root: false).as_json

      expect(json[:npn_critique_engagement]).to eq(score: -150, tier: "watch")
    end

    it "is never serialized for regular members" do
      create_npn_score(member)

      json = described_class.new(member, scope: member.guardian, root: false).as_json

      expect(json.keys).not_to include(:npn_critique_engagement)
    end

    it "is absent when the plugin is disabled" do
      create_npn_score(member)
      SiteSetting.npn_critique_engagement_enabled = false

      json = described_class.new(member, scope: staff.guardian, root: false).as_json

      expect(json.keys).not_to include(:npn_critique_engagement)
    end
  end
end

describe CurrentUserSerializer do
  fab!(:member) { Fabricate(:user, created_at: 3.months.ago) }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_nudge_enabled = true
  end

  describe "#npn_critique_nudge" do
    def nudge_json
      described_class.new(member, scope: member.guardian, root: false).as_json[:npn_critique_nudge]
    end

    it "is present for members below the nudge ratio" do
      create_npn_score(member)

      expect(nudge_json).to eq(created_topics: 6, topics_replied: 2)
    end

    it "is nil for members at a healthy ratio" do
      create_npn_score(member, created_topics: 2, topics_replied: 6, ratio: 3.0, tier: :healthy)

      expect(nudge_json).to be_nil
    end

    it "is nil for members inside the grace period" do
      create_npn_score(member, tier: :new_member)

      expect(nudge_json).to be_nil
    end

    it "is absent when nudges are disabled" do
      create_npn_score(member)
      SiteSetting.npn_critique_nudge_enabled = false

      json = described_class.new(member, scope: member.guardian, root: false).as_json

      expect(json.keys).not_to include(:npn_critique_nudge)
    end
  end
end
