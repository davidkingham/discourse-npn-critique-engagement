# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::Admin::OutreachController do
  fab!(:moderator)
  fab!(:member, :user)
  fab!(:healthy_member, :user)

  let(:period_start) { Time.zone.today.beginning_of_month }

  before do
    SiteSetting.npn_critique_engagement_enabled = true

    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: member.id,
      period_start: period_start,
      score: -250,
      tier: :priority_outreach,
      created_topics: 8,
      computed_at: Time.zone.now,
    )
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: healthy_member.id,
      period_start: period_start,
      score: 150,
      tier: :healthy,
      computed_at: Time.zone.now,
    )
  end

  it "is staff-only" do
    sign_in(member)

    get "/admin/plugins/critique-engagement/outreach.json"

    expect(response.status).to eq(404)
  end

  it "queues only priority-outreach members with their last contact" do
    DiscourseNpnCritiqueEngagement::OutreachLog.create!(
      user: member,
      staff_user: moderator,
      note: "Sent a friendly PM about give-and-take",
    )
    sign_in(moderator)

    get "/admin/plugins/critique-engagement/outreach.json"

    expect(response.status).to eq(200)
    rows = response.parsed_body["rows"]
    expect(rows.map { |row| row["username"] }).to contain_exactly(member.username)
    expect(rows.first["last_outreach"]["staff_username"]).to eq(moderator.username)
  end

  it "records outreach notes and lists a member's log" do
    sign_in(moderator)

    expect {
      post "/admin/plugins/critique-engagement/outreach/notes.json",
           params: {
             user_id: member.id,
             note: "Talked at the meetup",
           }
    }.to change(DiscourseNpnCritiqueEngagement::OutreachLog, :count).by(1)
    expect(response.status).to eq(201)

    get "/admin/plugins/critique-engagement/outreach/#{member.id}/notes.json"

    expect(response.parsed_body["notes"].first["note"]).to eq("Talked at the meetup")
  end

  it "rejects blank notes" do
    sign_in(moderator)

    post "/admin/plugins/critique-engagement/outreach/notes.json",
         params: {
           user_id: member.id,
           note: "",
         }

    expect(response.status).to eq(400)
  end
end
