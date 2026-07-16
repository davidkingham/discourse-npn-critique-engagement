# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::Admin::ReportsController do
  fab!(:moderator)
  fab!(:member, :user)

  let(:period_start) { Time.zone.today.beginning_of_month }

  before { SiteSetting.npn_critique_engagement_enabled = true }

  def create_score(user, period:, score:, tier: :watch)
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: user.id,
      period_start: period,
      score: score,
      tier: tier,
      computed_at: Time.zone.now,
    )
  end

  describe "#index" do
    it "is staff-only" do
      sign_in(member)

      get "/admin/plugins/critique-engagement/report.json"

      expect(response.status).to eq(404)
    end

    it "returns the month's rows with trend against the previous month" do
      create_score(member, period: period_start, score: 120, tier: :healthy)
      create_score(member, period: period_start.prev_month, score: 100, tier: :healthy)
      sign_in(moderator)

      get "/admin/plugins/critique-engagement/report.json"

      expect(response.status).to eq(200)
      row = response.parsed_body["rows"].first
      expect(row["username"]).to eq(member.username)
      expect(row["score"]).to eq(120.0)
      expect(row["trend"]).to eq(20.0)
      expect(response.parsed_body["periods"].length).to eq(2)
    end

    it "serves a requested past month and rejects malformed periods" do
      past = period_start.prev_month
      create_score(member, period: past, score: 80)
      sign_in(moderator)

      get "/admin/plugins/critique-engagement/report.json",
          params: {
            period: past.strftime("%Y-%m"),
          }
      expect(response.parsed_body["rows"].length).to eq(1)

      get "/admin/plugins/critique-engagement/report.json", params: { period: "junk" }
      expect(response.status).to eq(400)
    end
  end

  describe "#health" do
    it "summarizes tier distribution, volume, and median ratio per month" do
      create_score(member, period: period_start, score: 120, tier: :healthy)
      create_score(Fabricate(:user), period: period_start, score: -200, tier: :priority_outreach)
      sign_in(moderator)

      get "/admin/plugins/critique-engagement/health.json"

      expect(response.status).to eq(200)
      month = response.parsed_body["months"].first
      expect(month["members"]).to eq(2)
      expect(month["tiers"]["healthy"]).to eq(1)
      expect(month["tiers"]["priority_outreach"]).to eq(1)
      expect(month["tiers"]["excellent"]).to eq(0)
    end
  end
end
