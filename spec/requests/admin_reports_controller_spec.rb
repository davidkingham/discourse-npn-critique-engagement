# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::Admin::ReportsController do
  fab!(:moderator)
  fab!(:member, :user)

  let(:last_month) { 1.month.ago.beginning_of_month.to_date }

  before { SiteSetting.npn_critique_engagement_enabled = true }

  def create_score(user, score:, tier: :watch, ratio: 1.0)
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: user.id,
      score: score,
      tier: tier,
      ratio: ratio,
      computed_at: Time.zone.now,
    )
  end

  def create_snapshot(user, month:, score:, tier: :watch)
    DiscourseNpnCritiqueEngagement::MonthlySnapshot.create!(
      user_id: user.id,
      snapshot_month: month,
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

    it "returns the rolling standing with trend against the latest snapshot" do
      create_score(member, score: 120, tier: :healthy)
      create_snapshot(member, month: last_month, score: 100, tier: :healthy)
      sign_in(moderator)

      get "/admin/plugins/critique-engagement/report.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["period"]).to be_nil
      row = response.parsed_body["rows"].first
      expect(row["username"]).to eq(member.username)
      expect(row["score"]).to eq(120.0)
      expect(row["trend"]).to eq(20.0)
      expect(response.parsed_body["periods"]).to eq([last_month.to_s])
    end

    it "serves a snapshot month and rejects malformed or unknown periods" do
      create_snapshot(member, month: last_month, score: 80)
      sign_in(moderator)

      get "/admin/plugins/critique-engagement/report.json",
          params: {
            period: last_month.strftime("%Y-%m"),
          }
      expect(response.parsed_body["rows"].length).to eq(1)
      expect(response.parsed_body["period"]).to eq(last_month.to_s)

      get "/admin/plugins/critique-engagement/report.json", params: { period: "junk" }
      expect(response.status).to eq(400)

      get "/admin/plugins/critique-engagement/report.json", params: { period: "2019-01" }
      expect(response.status).to eq(404)
    end
  end

  describe "#health" do
    it "summarizes the live window first, then the snapshot months" do
      create_score(member, score: 120, tier: :healthy)
      create_score(Fabricate(:user), score: -200, tier: :priority_outreach)
      create_snapshot(member, month: last_month, score: 100, tier: :healthy)
      sign_in(moderator)

      get "/admin/plugins/critique-engagement/health.json"

      expect(response.status).to eq(200)
      months = response.parsed_body["months"]
      expect(months.first["current"]).to eq(true)
      expect(months.first["members"]).to eq(2)
      expect(months.first["tiers"]["healthy"]).to eq(1)
      expect(months.first["tiers"]["priority_outreach"]).to eq(1)
      expect(months.second["month"]).to eq(last_month.to_s)
      expect(months.second["members"]).to eq(1)
    end
  end
end
