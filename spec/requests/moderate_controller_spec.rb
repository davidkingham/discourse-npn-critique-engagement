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

    get "/moderate.json"

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

      get "/moderate.json"

      expect(response.status).to eq(200)
      coverage = response.parsed_body["coverage"]
      expect(coverage["total"]).to eq(3)
      expect(coverage["topics"].map { |topic| topic["id"] }).to eq(
        [newbie_topic.id, star_topic.id, veteran_topic.id],
      )
      expect(coverage["topics"].first["new_member"]).to eq(true)
      expect(coverage["topics"].first["tags"]).to eq(["landscape"])
    end

    it "clears topics once they receive a substantive critique, but not a short one" do
      answered = make_image_topic(veteran)
      Fabricate(:post, topic: answered, user: star_member, raw: "critique " * 20)
      brushed_off = make_image_topic(star_member)
      Fabricate(:post, topic: brushed_off, user: veteran, raw: "nice shot, love it a lot")

      get "/moderate.json"

      ids = response.parsed_body["coverage"]["topics"].map { |topic| topic["id"] }
      expect(ids).to contain_exactly(brushed_off.id)
    end

    it "ignores topics older than the coverage window" do
      make_image_topic(veteran, created_at: 20.days.ago)

      get "/moderate.json"

      expect(response.parsed_body["coverage"]["total"]).to eq(0)
    end

    it "ignores topics carrying a coverage-excluded tag when configured" do
      SiteSetting.npn_critique_coverage_excluded_tags = "showcase"
      showcase_tag = Fabricate(:tag, name: "showcase")
      make_image_topic(veteran, tag: showcase_tag)

      get "/moderate.json"

      expect(response.parsed_body["coverage"]["total"]).to eq(0)
    end

    it "covers weekly challenge entries but never the announcement topics" do
      challenge_tag = Fabricate(:tag, name: "weekly-challenge")
      entry = make_image_topic(veteran, tag: challenge_tag)
      announcement = make_image_topic(moderator, tag: challenge_tag)
      announcement.upsert_custom_fields(npn_weekly_challenge_slug: "2026-07-12-freshwater")
      # Announcements from before the plugin existed carry no marker — only
      # their title gives them away.
      old_announcement = make_image_topic(moderator, tag: challenge_tag)
      old_announcement.update!(title: "Weekly Challenge: Geological Wonders")

      get "/moderate.json"

      ids = response.parsed_body["coverage"]["topics"].map { |topic| topic["id"] }
      expect(ids).to contain_exactly(entry.id)
    end
  end

  describe "new member posts" do
    fab!(:new_members_category, :category)
    fab!(:intros) { Fabricate(:category, parent_category: new_members_category) }

    before do
      SiteSetting.npn_critique_new_member_category = new_members_category.id.to_s
      sign_in(moderator)
    end

    def make_new_member_topic(category)
      topic = Fabricate(:topic, category: category, user: newbie)
      Fabricate(:post, topic: topic, user: newbie)
      topic
    end

    it "surfaces posts across the subcategories until they have enough replies" do
      unanswered = make_new_member_topic(intros)
      one_reply = make_new_member_topic(new_members_category)
      Fabricate(:post, topic: one_reply, user: veteran, raw: "welcome aboard, glad you're here")
      handled = make_new_member_topic(intros)
      Fabricate(:post, topic: handled, user: veteran, raw: "welcome aboard, glad you're here")
      Fabricate(:post, topic: handled, user: star_member, raw: "great to have you with us here")

      get "/moderate.json"

      panel = response.parsed_body["new_members"]
      expect(panel["total"]).to eq(2)
      expect(panel["topics"].map { |topic| topic["id"] }).to eq([unanswered.id, one_reply.id])
      expect(panel["topics"].first["replies"]).to eq(0)
      expect(panel["topics"].first["subcategory"]).to eq(intros.name)
    end

    it "is empty when the category is not configured" do
      SiteSetting.npn_critique_new_member_category = ""
      make_new_member_topic(intros)

      get "/moderate.json"

      expect(response.parsed_body["new_members"]["total"]).to eq(0)
    end
  end

  describe "pick status" do
    before do
      sign_in(moderator)
      SiteSetting.npn_critique_pick_finalize_minutes = 0
    end

    it "reports per-genre pick status for the current week" do
      picked_topic = make_image_topic(veteran, created_at: 1.hour.ago)
      wildlife_tag = Fabricate(:tag, name: "wildlife")
      make_image_topic(star_member, tag: wildlife_tag, created_at: 1.hour.ago)

      post "/moderate/editors-picks/pick.json", params: { topic_id: picked_topic.id }

      get "/moderate.json"

      status = response.parsed_body["pick_status"].index_by { |genre| genre["tag"] }
      expect(status["landscape"]["picked"]).to eq(true)
      expect(status["landscape"]["picked_by"]).to eq(moderator.username)
      expect(status["wildlife"]["picked"]).to eq(false)
    end

    it "counts a pick made this week even when the image was posted last week" do
      last_week = Date.current.beginning_of_week(:sunday) - 3.days
      image = make_image_topic(veteran, created_at: last_week.to_time)

      post "/moderate/editors-picks/pick.json", params: { topic_id: image.id, genre: "landscape" }

      get "/moderate.json"

      status = response.parsed_body["pick_status"].index_by { |genre| genre["tag"] }
      expect(status["landscape"]["picked"]).to eq(true)
      expect(status["landscape"]["picked_by"]).to eq(moderator.username)
    end

    it "resets on Sunday — picks made before the week began no longer count" do
      last_week = Date.current.beginning_of_week(:sunday) - 3.days
      image = make_image_topic(veteran, created_at: last_week.to_time)
      post "/moderate/editors-picks/pick.json", params: { topic_id: image.id, genre: "landscape" }
      Post.where(topic_id: image.id, action_code: "npn_editors_pick").update_all(
        created_at: last_week.to_time,
      )

      get "/moderate.json"

      status = response.parsed_body["pick_status"].index_by { |genre| genre["tag"] }
      expect(status["landscape"]["picked"]).to eq(false)
    end

    it "counts a staged pick for its genre so nobody double-picks it" do
      wildlife_tag = Fabricate(:tag, name: "wildlife")
      staged = make_image_topic(veteran, created_at: 1.hour.ago)
      make_image_topic(star_member, tag: wildlife_tag, created_at: 1.hour.ago)
      DiscourseNpnCritiqueEngagement::PendingPick.create!(
        topic_id: staged.id,
        user_id: moderator.id,
        genre: "landscape",
        finalize_at: 10.minutes.from_now,
      )

      get "/moderate.json"

      status = response.parsed_body["pick_status"].index_by { |genre| genre["tag"] }
      expect(status["landscape"]["picked"]).to eq(true)
      expect(status["landscape"]["picked_by"]).to eq(moderator.username)
      expect(status["wildlife"]["picked"]).to eq(false)
    end

    it "counts a cross-tagged pick only for its declared genre" do
      wildlife_tag = Fabricate(:tag, name: "wildlife")
      cross_tagged = make_image_topic(veteran, created_at: 1.hour.ago)
      cross_tagged.tags << wildlife_tag

      post "/moderate/editors-picks/pick.json",
           params: {
             topic_id: cross_tagged.id,
             genre: "wildlife",
           }

      get "/moderate.json"

      status = response.parsed_body["pick_status"].index_by { |genre| genre["tag"] }
      expect(status["wildlife"]["picked"]).to eq(true)
      expect(status["landscape"]["picked"]).to eq(false)
    end

    it "keeps style and attribute tags off the pick board" do
      style_tag = Fabricate(:tag, name: "black-and-white")
      make_image_topic(veteran, tag: style_tag, created_at: 1.hour.ago)
      make_image_topic(star_member, created_at: 1.hour.ago)

      get "/moderate.json"

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

    get "/moderate.json"

    expect(response.parsed_body["outreach"].map { |row| row["username"] }).to eq([veteran.username])
    expect(response.parsed_body["welcome"].map { |row| row["username"] }).to eq([newbie.username])
  end
end
