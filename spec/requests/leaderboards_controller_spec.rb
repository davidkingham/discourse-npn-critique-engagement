# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::LeaderboardsController do
  fab!(:top_critic, :user)
  fab!(:runner_up, :user)
  fab!(:struggling_member, :user)

  let(:period_start) { Time.zone.today.beginning_of_month }

  before { SiteSetting.npn_critique_engagement_enabled = true }

  def create_score(user, weighted:, tier:, period: period_start, finalized: false)
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: user.id,
      period_start: period,
      score: weighted * 100,
      tier: tier,
      weighted_replies: weighted,
      topics_replied: weighted.round,
      computed_at: Time.zone.now,
      finalized: finalized,
    )
  end

  describe "#show" do
    before do
      create_score(top_critic, weighted: 12.5, tier: :excellent)
      create_score(runner_up, weighted: 6.2, tier: :healthy)
      create_score(struggling_member, weighted: 1.1, tier: :watch)
    end

    it "ranks the month's critics by weighted count without exposing raw scores" do
      get "/critique-engagement/leaderboard.json"

      expect(response.status).to eq(200)
      entries = response.parsed_body["entries"]
      expect(entries.map { |entry| entry["username"] }).to eq(
        [top_critic.username, runner_up.username, struggling_member.username],
      )
      expect(entries.first["weighted_replies"]).to eq(12.5)
      expect(entries.first.keys).not_to include("score")
    end

    it "never shows a below-healthy tier publicly" do
      get "/critique-engagement/leaderboard.json"

      tiers = response.parsed_body["entries"].map { |entry| entry["tier"] }
      expect(tiers).to eq(%w[excellent healthy] + [nil])
    end

    it "limits entries to the configured leaderboard size" do
      SiteSetting.npn_critique_leaderboard_size = 2

      get "/critique-engagement/leaderboard.json"

      expect(response.parsed_body["entries"].length).to eq(2)
    end

    it "is unavailable when the plugin is disabled" do
      SiteSetting.npn_critique_engagement_enabled = false

      get "/critique-engagement/leaderboard.json"

      expect(response.status).to eq(404)
    end
  end

  describe "#hall_of_fame" do
    it "lists each finalized season's winner" do
      create_score(
        top_critic,
        weighted: 9.0,
        tier: :excellent,
        period: 2.months.ago.beginning_of_month,
        finalized: true,
      )
      create_score(
        runner_up,
        weighted: 4.0,
        tier: :healthy,
        period: 2.months.ago.beginning_of_month,
        finalized: true,
      )
      create_score(
        runner_up,
        weighted: 7.0,
        tier: :excellent,
        period: 1.month.ago.beginning_of_month,
        finalized: true,
      )
      create_score(struggling_member, weighted: 20.0, tier: :excellent) # current month: not finalized

      get "/critique-engagement/hall-of-fame.json"

      expect(response.status).to eq(200)
      seasons = response.parsed_body["seasons"]
      expect(seasons.map { |season| season["username"] }).to eq(
        [runner_up.username, top_critic.username],
      )
    end

    it "lists pillar badge holders" do
      badge = DiscourseNpnCritiqueEngagement::Badges.pillar
      BadgeGranter.grant(badge, top_critic)

      get "/critique-engagement/hall-of-fame.json"

      expect(response.parsed_body["pillars"].map { |pillar| pillar["username"] }).to eq(
        [top_critic.username],
      )
    end
  end
end
