# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::Admin::OutreachController do
  fab!(:moderator)
  fab!(:member, :user)
  fab!(:healthy_member, :user)

  before do
    SiteSetting.npn_critique_engagement_enabled = true

    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: member.id,
      score: -250,
      tier: :priority_outreach,
      created_topics: 8,
      computed_at: Time.zone.now,
    )
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: healthy_member.id,
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

  it "lists promising new members to welcome, separate from the outreach queue" do
    newbie = Fabricate(:user)
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: newbie.id,
      score: 40,
      tier: :new_member,
      weighted_replies: 2.5,
      topics_replied: 3,
      computed_at: Time.zone.now,
    )
    sign_in(moderator)

    get "/admin/plugins/critique-engagement/outreach.json"

    expect(response.parsed_body["welcome_rows"].map { |row| row["username"] }).to contain_exactly(
      newbie.username,
    )
    expect(response.parsed_body["rows"].map { |row| row["username"] }).to contain_exactly(
      member.username,
    )
  end

  it "surfaces each member's top genre tags for the right moderator to reach out" do
    SiteSetting.npn_critique_category = Fabricate(:category).id.to_s
    category = Category.find(SiteSetting.npn_critique_category.to_i)
    landscape = Fabricate(:tag, name: "landscape")
    wildlife = Fabricate(:tag, name: "wildlife")
    style = Fabricate(:tag, name: "black-and-white")
    2.times do
      topic = Fabricate(:topic, category: category, user: member, tags: [landscape, style])
      Fabricate(:post, topic: topic, user: member)
    end
    topic = Fabricate(:topic, category: category, user: member, tags: [wildlife])
    Fabricate(:post, topic: topic, user: member)
    sign_in(moderator)

    get "/admin/plugins/critique-engagement/outreach.json"

    row = response.parsed_body["rows"].find { |entry| entry["username"] == member.username }
    expect(row["top_tags"]).to eq(
      [{ "tag" => "landscape", "count" => 2 }, { "tag" => "wildlife", "count" => 1 }],
    )
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
