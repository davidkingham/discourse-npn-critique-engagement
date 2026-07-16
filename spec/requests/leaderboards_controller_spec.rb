# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::LeaderboardsController do
  fab!(:top_critic, :user)
  fab!(:runner_up, :user)
  fab!(:struggling_member, :user)

  before { SiteSetting.npn_critique_engagement_enabled = true }

  def create_score(user, weighted:, tier:)
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: user.id,
      score: weighted * 100,
      tier: tier,
      weighted_replies: weighted,
      topics_replied: weighted.round,
      computed_at: Time.zone.now,
    )
  end

  def create_snapshot(user, month:, weighted:, tier: :excellent)
    DiscourseNpnCritiqueEngagement::MonthlySnapshot.create!(
      user_id: user.id,
      snapshot_month: month,
      score: weighted * 100,
      tier: tier,
      weighted_replies: weighted,
      computed_at: Time.zone.now,
    )
  end

  describe "#show" do
    before do
      create_score(top_critic, weighted: 12.5, tier: :excellent)
      create_score(runner_up, weighted: 6.2, tier: :healthy)
      create_score(struggling_member, weighted: 1.1, tier: :watch)
    end

    it "ranks the window's critics by weighted count without exposing raw scores" do
      get "/critique-engagement/leaderboard.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["window_days"]).to eq(SiteSetting.npn_critique_window_days)
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
    it "lists each snapshot month's winner" do
      two_months_ago = 2.months.ago.beginning_of_month.to_date
      last_month = 1.month.ago.beginning_of_month.to_date
      create_snapshot(top_critic, month: two_months_ago, weighted: 9.0)
      create_snapshot(runner_up, month: two_months_ago, weighted: 4.0, tier: :healthy)
      create_snapshot(runner_up, month: last_month, weighted: 7.0)

      get "/critique-engagement/hall-of-fame.json"

      expect(response.status).to eq(200)
      seasons = response.parsed_body["seasons"]
      expect(seasons.map { |season| season["username"] }).to eq(
        [runner_up.username, top_critic.username],
      )
    end

    it "lists steward badge holders and rising critics" do
      BadgeGranter.grant(DiscourseNpnCritiqueEngagement::Badges.pillar, top_critic)
      BadgeGranter.grant(DiscourseNpnCritiqueEngagement::Badges.rising, runner_up)

      get "/critique-engagement/hall-of-fame.json"

      expect(response.parsed_body["pillars"].map { |pillar| pillar["username"] }).to eq(
        [top_critic.username],
      )
      expect(response.parsed_body["rising"].map { |critic| critic["username"] }).to eq(
        [runner_up.username],
      )
    end
  end
end
