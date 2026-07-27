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

  describe "claims" do
    fab!(:other_moderator, :moderator)

    before { sign_in(moderator) }

    it "lets a moderator claim an outreach, visible to everyone" do
      post "/admin/plugins/critique-engagement/outreach/claim.json", params: { user_id: member.id }

      expect(response.status).to eq(201)
      expect(response.parsed_body["mine"]).to eq(true)

      sign_in(other_moderator)
      get "/admin/plugins/critique-engagement/outreach.json"
      row = response.parsed_body["rows"].find { |entry| entry["username"] == member.username }
      expect(row["claim"]["username"]).to eq(moderator.username)
      expect(row["claim"]["mine"]).to eq(false)
    end

    it "rejects claiming a member someone else already claimed" do
      DiscourseNpnCritiqueEngagement::OutreachClaim.create!(
        user_id: member.id,
        staff_user: other_moderator,
      )

      post "/admin/plugins/critique-engagement/outreach/claim.json", params: { user_id: member.id }

      expect(response.status).to eq(409)
    end

    it "lets a stale claim be taken over" do
      DiscourseNpnCritiqueEngagement::OutreachClaim.create!(
        user_id: member.id,
        staff_user: other_moderator,
        created_at: 10.days.ago,
      )

      post "/admin/plugins/critique-engagement/outreach/claim.json", params: { user_id: member.id }

      expect(response.status).to eq(201)
      expect(
        DiscourseNpnCritiqueEngagement::OutreachClaim.find_by(user_id: member.id).staff_user_id,
      ).to eq(moderator.id)
    end

    it "resolves the claim when the contact note is logged" do
      DiscourseNpnCritiqueEngagement::OutreachClaim.create!(
        user_id: member.id,
        staff_user: moderator,
      )

      post "/admin/plugins/critique-engagement/outreach/notes.json",
           params: {
             user_id: member.id,
             note: "Sent a friendly PM",
           }

      expect(DiscourseNpnCritiqueEngagement::OutreachClaim.where(user_id: member.id)).to be_empty
    end

    it "reminds the claimer once when the contact goes unlogged past the window" do
      claim =
        DiscourseNpnCritiqueEngagement::OutreachClaim.create!(
          user_id: member.id,
          staff_user: moderator,
          created_at: 25.hours.ago,
        )
      fresh_claim =
        DiscourseNpnCritiqueEngagement::OutreachClaim.create!(
          user_id: healthy_member.id,
          staff_user: moderator,
          created_at: 1.hour.ago,
        )

      expect { DiscourseNpnCritiqueEngagement::OutreachClaim.send_reminders }.to change {
        Topic.private_messages.count
      }.by(1)

      pm = Topic.private_messages.order(created_at: :desc).first
      expect(pm.topic_allowed_users.pluck(:user_id)).to include(moderator.id)
      expect(pm.first_post.raw).to include(member.username)
      expect(claim.reload.reminded_at).to be_present
      expect(fresh_claim.reload.reminded_at).to be_nil

      expect { DiscourseNpnCritiqueEngagement::OutreachClaim.send_reminders }.not_to change {
        Topic.private_messages.count
      }
    end

    it "sends no reminders when the reminder window is disabled" do
      SiteSetting.npn_critique_claim_reminder_hours = 0
      DiscourseNpnCritiqueEngagement::OutreachClaim.create!(
        user_id: member.id,
        staff_user: moderator,
        created_at: 25.hours.ago,
      )

      expect { DiscourseNpnCritiqueEngagement::OutreachClaim.send_reminders }.not_to change {
        Topic.private_messages.count
      }
    end

    it "lets the claimer release their own claim" do
      DiscourseNpnCritiqueEngagement::OutreachClaim.create!(
        user_id: member.id,
        staff_user: moderator,
      )

      delete "/admin/plugins/critique-engagement/outreach/claim.json",
             params: {
               user_id: member.id,
             }

      expect(response.status).to eq(204)
      expect(DiscourseNpnCritiqueEngagement::OutreachClaim.where(user_id: member.id)).to be_empty
    end
  end

  describe "exclusions" do
    before { sign_in(moderator) }

    it "takes a member off the queue into a visible set-aside list, and puts them back" do
      post "/admin/plugins/critique-engagement/outreach/exclusion.json",
           params: {
             user_id: member.id,
             reason: "Contacted six times over three years, no change. Time to let him be.",
           }

      expect(response.status).to eq(201)
      expect(response.parsed_body["expires_at"]).to be_nil

      get "/admin/plugins/critique-engagement/outreach.json"
      expect(response.parsed_body["rows"]).to be_empty
      excluded = response.parsed_body["excluded_rows"]
      expect(excluded.map { |row| row["username"] }).to contain_exactly(member.username)
      expect(excluded.first["exclusion"]["username"]).to eq(moderator.username)
      expect(excluded.first["exclusion"]["reason"]).to include("no change")

      delete "/admin/plugins/critique-engagement/outreach/exclusion.json",
             params: {
               user_id: member.id,
             }
      expect(response.status).to eq(204)

      get "/admin/plugins/critique-engagement/outreach.json"
      expect(response.parsed_body["rows"].map { |row| row["username"] }).to contain_exactly(
        member.username,
      )
      expect(response.parsed_body["excluded_rows"]).to be_empty
    end

    it "leaves the member's score and tier alone" do
      post "/admin/plugins/critique-engagement/outreach/exclusion.json",
           params: {
             user_id: member.id,
             reason: "Not going to change",
           }

      score = DiscourseNpnCritiqueEngagement::Score.find_by(user_id: member.id)
      expect(score.tier).to eq("priority_outreach")
      expect(score.score).to eq(-250)
    end

    it "returns the member to the queue once a timed exclusion runs out" do
      post "/admin/plugins/critique-engagement/outreach/exclusion.json",
           params: {
             user_id: member.id,
             reason: "Give him six months",
             days: 180,
           }

      get "/admin/plugins/critique-engagement/outreach.json"
      expect(response.parsed_body["rows"]).to be_empty

      freeze_time(181.days.from_now) do
        sign_in(moderator) # the original session has aged out by now
        get "/admin/plugins/critique-engagement/outreach.json"

        expect(response.parsed_body["rows"].map { |row| row["username"] }).to contain_exactly(
          member.username,
        )
        expect(response.parsed_body["excluded_rows"]).to be_empty
      end
    end

    it "releases an outstanding claim and refuses new ones" do
      DiscourseNpnCritiqueEngagement::OutreachClaim.create!(
        user_id: member.id,
        staff_user: moderator,
      )

      post "/admin/plugins/critique-engagement/outreach/exclusion.json",
           params: {
             user_id: member.id,
             reason: "Not going to change",
           }

      expect(DiscourseNpnCritiqueEngagement::OutreachClaim.where(user_id: member.id)).to be_empty

      post "/admin/plugins/critique-engagement/outreach/claim.json", params: { user_id: member.id }
      expect(response.status).to eq(409)
    end

    it "stops chasing the claimer about a member set aside after they claimed" do
      DiscourseNpnCritiqueEngagement::OutreachClaim.create!(
        user_id: member.id,
        staff_user: moderator,
        created_at: 25.hours.ago,
      )
      DiscourseNpnCritiqueEngagement::OutreachExclusion.create!(
        user_id: member.id,
        staff_user: moderator,
        reason: "Not going to change",
      )

      expect { DiscourseNpnCritiqueEngagement::OutreachClaim.send_reminders }.not_to change {
        Topic.private_messages.count
      }
    end

    it "rejects an exclusion with no reason" do
      post "/admin/plugins/critique-engagement/outreach/exclusion.json",
           params: {
             user_id: member.id,
             reason: "   ",
           }

      expect(response.status).to eq(400)
      expect(DiscourseNpnCritiqueEngagement::OutreachExclusion.count).to eq(0)
    end
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
