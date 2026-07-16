# frozen_string_literal: true

require "rails_helper"

describe Jobs::NpnCritiqueScoresRefresh do
  fab!(:category)
  fab!(:critic) { Fabricate(:user, created_at: 3.months.ago) }
  fab!(:poster) { Fabricate(:user, created_at: 3.months.ago) }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = category.id.to_s

    topic = Fabricate(:topic, category: category, user: poster)
    Fabricate(:post, topic: topic, user: poster)
    Fabricate(:post, topic: topic, user: critic, raw: "critique " * 20)
  end

  it "computes the current month's scores" do
    expect { described_class.new.execute({}) }.to change(
      DiscourseNpnCritiqueEngagement::Score,
      :count,
    ).by(2)
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.npn_critique_engagement_enabled = false

    expect { described_class.new.execute({}) }.not_to change(
      DiscourseNpnCritiqueEngagement::Score,
      :count,
    )
  end

  it "does nothing without a configured category" do
    SiteSetting.npn_critique_category = ""

    expect { described_class.new.execute({}) }.not_to change(
      DiscourseNpnCritiqueEngagement::Score,
      :count,
    )
  end
end
