# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::ModerateController do
  fab!(:moderator)
  fab!(:category)
  fab!(:landscape_tag) { Fabricate(:tag, name: "landscape") }
  fab!(:veteran) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:star_member) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:newbie) { Fabricate(:user, created_at: 5.days.ago) }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = category.id.to_s
  end

  def make_image_topic(user, tag: landscape_tag, created_at: 1.day.ago)
    topic = Fabricate(:topic, category: category, user: user, tags: [tag], created_at: created_at)
    Fabricate(:post, topic: topic, user: user, created_at: created_at)
    topic
  end

  it "is staff-only" do
    sign_in(veteran)

    get "/critique-engagement/moderate.json"

    expect(response.status).to eq(403)
  end

  describe "coverage" do
    before { sign_in(moderator) }

    it "lists unanswered topics with new members first, then by standing" do
      DiscourseNpnCritiqueEngagement::Score.create!(
        user_id: star_member.id,
        score: 300,
        tier: :excellent,
        computed_at: Time.zone.now,
      )
      veteran_topic = make_image_topic(veteran, created_at: 3.days.ago)
      star_topic = make_image_topic(star_member, created_at: 1.day.ago)
      newbie_topic = make_image_topic(newbie, created_at: 2.hours.ago)

      get "/critique-engagement/moderate.json"

      expect(response.status).to eq(200)
      coverage = response.parsed_body["coverage"]
      expect(coverage["total"]).to eq(3)
      expect(coverage["topics"].map { |topic| topic["id"] }).to eq(
        [newbie_topic.id, star_topic.id, veteran_topic.id],
      )
      expect(coverage["topics"].first["new_member"]).to eq(true)
    end

    it "clears topics once they receive a substantive critique, but not a short one" do
      answered = make_image_topic(veteran)
      Fabricate(:post, topic: answered, user: star_member, raw: "critique " * 20)
      brushed_off = make_image_topic(star_member)
      Fabricate(:post, topic: brushed_off, user: veteran, raw: "nice shot, love it a lot")

      get "/critique-engagement/moderate.json"

      ids = response.parsed_body["coverage"]["topics"].map { |topic| topic["id"] }
      expect(ids).to contain_exactly(brushed_off.id)
    end

    it "ignores topics older than the coverage window" do
      make_image_topic(veteran, created_at: 20.days.ago)

      get "/critique-engagement/moderate.json"

      expect(response.parsed_body["coverage"]["total"]).to eq(0)
    end

    it "ignores topics carrying a coverage-excluded tag" do
      challenge_tag = Fabricate(:tag, name: "weekly-challenge")
      make_image_topic(veteran, tag: challenge_tag)

      get "/critique-engagement/moderate.json"

      expect(response.parsed_body["coverage"]["total"]).to eq(0)
    end
  end

  describe "pick status" do
    before { sign_in(moderator) }

    it "reports per-genre pick status for the current week" do
      picked_topic = make_image_topic(veteran, created_at: 1.hour.ago)
      wildlife_tag = Fabricate(:tag, name: "wildlife")
      make_image_topic(star_member, tag: wildlife_tag, created_at: 1.hour.ago)

      post "/critique-engagement/editors-picks/pick.json", params: { topic_id: picked_topic.id }

      get "/critique-engagement/moderate.json"

      status = response.parsed_body["pick_status"].index_by { |genre| genre["tag"] }
      expect(status["landscape"]["picked"]).to eq(true)
      expect(status["landscape"]["picked_by"]).to eq(moderator.username)
      expect(status["wildlife"]["picked"]).to eq(false)
    end

    it "keeps style and attribute tags off the pick board" do
      style_tag = Fabricate(:tag, name: "black-and-white")
      make_image_topic(veteran, tag: style_tag, created_at: 1.hour.ago)
      make_image_topic(star_member, created_at: 1.hour.ago)

      get "/critique-engagement/moderate.json"

      expect(response.parsed_body["pick_status"].map { |genre| genre["tag"] }).to eq(["landscape"])
    end
  end

  it "includes the outreach and welcome mini lists" do
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: veteran.id,
      score: -250,
      tier: :priority_outreach,
      created_topics: 8,
      computed_at: Time.zone.now,
    )
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: newbie.id,
      score: 40,
      tier: :new_member,
      weighted_replies: 2.0,
      computed_at: Time.zone.now,
    )
    sign_in(moderator)

    get "/critique-engagement/moderate.json"

    expect(response.parsed_body["outreach"].map { |row| row["username"] }).to eq([veteran.username])
    expect(response.parsed_body["welcome"].map { |row| row["username"] }).to eq([newbie.username])
  end
end
