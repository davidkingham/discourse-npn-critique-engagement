# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::Recognition do
  fab!(:guide_member, :user)
  fab!(:healthy_member, :user)
  fab!(:watch_member, :user)

  before { SiteSetting.npn_critique_engagement_enabled = true }

  def create_score(user, tier:)
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: user.id,
      score: 100,
      tier: tier,
      computed_at: Time.zone.now,
    )
  end

  it "marks currently-excellent members as guides and nothing below the chip tier" do
    create_score(guide_member, tier: :excellent)
    create_score(healthy_member, tier: :healthy)
    create_score(watch_member, tier: :watch)
    described_class.rebuild!

    expect(described_class.level_for(guide_member.id)).to eq("guide")
    expect(described_class.level_for(healthy_member.id)).to be_nil
    expect(described_class.level_for(watch_member.id)).to be_nil
  end

  it "marks healthy members as contributors when the chip tier is lowered" do
    SiteSetting.npn_critique_chip_min_tier = "healthy"
    create_score(healthy_member, tier: :healthy)
    described_class.rebuild!

    expect(described_class.level_for(healthy_member.id)).to eq("contributor")
  end

  it "steward badge holders outrank their current standing" do
    create_score(guide_member, tier: :excellent)
    BadgeGranter.grant(DiscourseNpnCritiqueEngagement::Badges.pillar, guide_member)
    described_class.rebuild!

    expect(described_class.level_for(guide_member.id)).to eq("steward")
  end

  describe "post serialization" do
    fab!(:post_record) { Fabricate(:post, user: guide_member) }

    def serialized_recognition
      PostSerializer.new(post_record, scope: Guardian.new, root: false).as_json[
        :npn_critique_recognition
      ]
    end

    it "serializes the chip level on posts for everyone" do
      create_score(guide_member, tier: :excellent)
      described_class.rebuild!

      expect(serialized_recognition).to eq("guide")
    end

    it "is absent for unrecognized posters" do
      create_score(guide_member, tier: :watch)
      described_class.rebuild!

      expect(
        PostSerializer.new(post_record, scope: Guardian.new, root: false).as_json.keys,
      ).not_to include(:npn_critique_recognition)
    end

    it "is absent when chips are disabled" do
      create_score(guide_member, tier: :excellent)
      described_class.rebuild!
      SiteSetting.npn_critique_chips_enabled = false

      expect(
        PostSerializer.new(post_record, scope: Guardian.new, root: false).as_json.keys,
      ).not_to include(:npn_critique_recognition)
    end
  end

  describe "user card serialization" do
    it "serializes the chip level publicly" do
      create_score(guide_member, tier: :excellent)
      described_class.rebuild!

      json = UserCardSerializer.new(guide_member, scope: Guardian.new, root: false).as_json
      expect(json[:npn_critique_recognition]).to eq("guide")
    end
  end
end
