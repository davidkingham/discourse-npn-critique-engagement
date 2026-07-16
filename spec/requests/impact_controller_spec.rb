# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::ImpactController do
  fab!(:member) { Fabricate(:user, created_at: 6.months.ago) }

  before { SiteSetting.npn_critique_engagement_enabled = true }

  def create_score(attributes = {})
    DiscourseNpnCritiqueEngagement::Score.create!(
      {
        user_id: member.id,
        score: 150,
        tier: :healthy,
        weighted_replies: 4.0,
        created_topics: 2,
        topics_replied: 4,
        ratio: 2.0,
        computed_at: Time.zone.now,
      }.merge(attributes),
    )
  end

  def create_snapshot(month, attributes = {})
    DiscourseNpnCritiqueEngagement::MonthlySnapshot.create!(
      {
        user_id: member.id,
        snapshot_month: month,
        score: 150,
        tier: :healthy,
        weighted_replies: 4.0,
        computed_at: Time.zone.now,
      }.merge(attributes),
    )
  end

  it "requires login" do
    get "/critique-engagement/impact.json"

    expect(response.status).to eq(403)
  end

  it "returns the member's own standing and history without the raw score" do
    create_score
    create_snapshot(1.month.ago.beginning_of_month.to_date, tier: :watch)
    sign_in(member)

    get "/critique-engagement/impact.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["window_days"]).to eq(SiteSetting.npn_critique_window_days)
    current = response.parsed_body["current"]
    expect(current["tier"]).to eq("healthy")
    expect(current["weighted_replies"]).to eq(4.0)
    expect(current.keys).not_to include("score")
    history = response.parsed_body["history"]
    expect(history.length).to eq(1)
    expect(history.first["month"]).to eq(1.month.ago.beginning_of_month.to_date.to_s)
  end

  it "suggests a concrete next action toward the next tier" do
    create_score(score: 150, tier: :healthy)
    sign_in(member)

    get "/critique-engagement/impact.json"

    next_action = response.parsed_body["next_action"]
    expect(next_action["type"]).to eq("critiques_needed")
    expect(next_action["target_tier"]).to eq("excellent")
    expect(next_action["count"]).to be >= 1
  end

  it "celebrates members already at the top" do
    create_score(score: 500, tier: :excellent)
    sign_in(member)

    get "/critique-engagement/impact.json"

    expect(response.parsed_body["next_action"]["type"]).to eq("at_top")
  end

  it "suggests starting when there is no activity in the window" do
    sign_in(member)

    get "/critique-engagement/impact.json"

    expect(response.parsed_body["next_action"]["type"]).to eq("start")
    expect(response.parsed_body["current"]).to be_nil
  end

  it "reports steward badge progress from snapshot history" do
    create_snapshot(1.month.ago.beginning_of_month.to_date, tier: :excellent)
    create_snapshot(2.months.ago.beginning_of_month.to_date, tier: :excellent)
    sign_in(member)

    get "/critique-engagement/impact.json"

    pillar = response.parsed_body["badge_progress"]["pillar"]
    expect(pillar["excellent_months"]).to eq(2)
    expect(pillar["required_months"]).to eq(SiteSetting.npn_critique_pillar_required_months)
  end
end
