# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::EditorsPicksController do
  fab!(:moderator)
  fab!(:category)
  fab!(:landscape_tag) { Fabricate(:tag, name: "landscape") }
  fab!(:wildlife_tag) { Fabricate(:tag, name: "wildlife") }
  fab!(:engaged_poster, :user)
  fab!(:quiet_poster, :user)

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = category.id.to_s

    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: engaged_poster.id,
      score: 300,
      tier: :healthy,
      topics_replied: 6,
      created_topics: 2,
      computed_at: Time.zone.now,
    )
  end

  def make_image_topic(user, tag)
    topic = Fabricate(:topic, category: category, user: user, tags: [tag])
    Fabricate(:post, topic: topic, user: user)
    topic
  end

  it "is staff-only" do
    sign_in(engaged_poster)

    get "/moderate/editors-picks.json"

    expect(response.status).to eq(403)
  end

  # HTML navigations always get the app shell (check_xhr renders it before
  # controller gates run); access control lives in the Ember route redirect
  # and the staff-gated JSON endpoints.
  it "serves the outreach and report page shells" do
    sign_in(moderator)

    get "/moderate/outreach"
    expect(response.status).to eq(200)

    get "/moderate/report"
    expect(response.status).to eq(200)
  end

  it "redirects the tools' original URLs to /moderate" do
    sign_in(moderator)

    get "/critique-engagement/editors-picks"
    expect(response).to redirect_to("/moderate/editors-picks")

    get "/critique-engagement/outreach"
    expect(response).to redirect_to("/moderate/outreach")

    get "/critique-engagement/moderate"
    expect(response).to redirect_to("/moderate")
  end

  describe "#show" do
    fab!(:engaged_topic) { make_image_topic(engaged_poster, landscape_tag) }
    fab!(:quiet_topic) { make_image_topic(quiet_poster, landscape_tag) }
    fab!(:wildlife_topic) { make_image_topic(quiet_poster, wildlife_tag) }

    before { sign_in(moderator) }

    it "lists the week's images sorted by poster standing" do
      get "/moderate/editors-picks.json"

      expect(response.status).to eq(200)
      topics = response.parsed_body["topics"]
      expect(topics.map { |topic| topic["id"] }).to eq(
        [engaged_topic.id, quiet_topic.id, wildlife_topic.id],
      )
      expect(topics.first["score"]["tier"]).to eq("healthy")
      expect(topics.second["score"]).to be_nil
      expect(response.parsed_body["tags"]).to contain_exactly("landscape", "wildlife")
    end

    it "filters by tag" do
      get "/moderate/editors-picks.json", params: { tag: "wildlife" }

      expect(response.parsed_body["topics"].map { |topic| topic["id"] }).to eq([wildlife_topic.id])
    end

    it "excludes other weeks and other categories" do
      old_topic = make_image_topic(quiet_poster, landscape_tag)
      old_topic.update!(created_at: 2.weeks.ago)
      elsewhere = Fabricate(:topic, user: quiet_poster, tags: [landscape_tag])
      Fabricate(:post, topic: elsewhere, user: quiet_poster)

      get "/moderate/editors-picks.json"

      ids = response.parsed_body["topics"].map { |topic| topic["id"] }
      expect(ids).not_to include(old_topic.id)
      expect(ids).not_to include(elsewhere.id)
    end
  end

  describe "#pick" do
    fab!(:topic) { make_image_topic(engaged_poster, landscape_tag) }

    before { sign_in(moderator) }

    it "applies the pick tag and posts a public small-action note" do
      post "/moderate/editors-picks/pick.json", params: { topic_id: topic.id }

      expect(response.status).to eq(200)
      expect(topic.reload.tags.map(&:name)).to include("editors-pick")

      note = topic.posts.order(:created_at).last
      expect(note.post_type).to eq(Post.types[:small_action])
      expect(note.action_code).to eq("npn_editors_pick")
      expect(note.user_id).to eq(moderator.id)

      get "/moderate/editors-picks.json"
      picked = response.parsed_body["topics"].find { |entry| entry["id"] == topic.id }
      expect(picked["picked"]).to eq(true)
      expect(picked["picked_by"]["username"]).to eq(moderator.username)
      expect(response.parsed_body["tags"]).not_to include("editors-pick")
    end

    it "grants the post-tied Editor's Pick badge and sends a congratulations PM" do
      post "/moderate/editors-picks/pick.json", params: { topic_id: topic.id }

      badge = Badge.find_by(name: SiteSetting.npn_critique_editors_pick_badge_name)
      user_badge = UserBadge.find_by(badge: badge, user: engaged_poster)
      expect(user_badge.post_id).to eq(topic.first_post.id)
      expect(user_badge.granted_by_id).to eq(moderator.id)

      pm =
        Topic
          .private_messages
          .joins(:topic_allowed_users)
          .where(topic_allowed_users: { user_id: engaged_poster.id })
          .order(created_at: :desc)
          .first
      expect(pm).to be_present
      expect(pm.first_post.raw).to include(topic.title)
    end

    it "skips the badge and PM when disabled" do
      SiteSetting.npn_critique_editors_pick_badge_name = ""
      SiteSetting.npn_critique_editors_pick_pm_enabled = false

      post "/moderate/editors-picks/pick.json", params: { topic_id: topic.id }

      expect(response.status).to eq(200)
      expect(UserBadge.count).to eq(0)
      expect(Topic.private_messages.count).to eq(0)
    end

    it "records the declared genre and posts the public reason as the note body" do
      topic.tags << wildlife_tag

      post "/moderate/editors-picks/pick.json",
           params: {
             topic_id: topic.id,
             genre: "wildlife",
             reason: "Wonderful light and a decisive moment.",
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["picked_by"]["genre"]).to eq("wildlife")

      note = topic.posts.order(:created_at).last
      expect(note.raw).to eq("Wonderful light and a decisive moment.")
      expect(note.custom_fields["npn_editors_pick_genre"]).to eq("wildlife")

      get "/moderate/editors-picks.json"
      picked = response.parsed_body["topics"].find { |entry| entry["id"] == topic.id }
      expect(picked["picked_by"]["genre"]).to eq("wildlife")
      expect(picked["genre_options"]).to contain_exactly("landscape", "wildlife")
    end

    it "rejects a genre the topic isn't tagged with and an overlong reason" do
      post "/moderate/editors-picks/pick.json", params: { topic_id: topic.id, genre: "wildlife" }
      expect(response.status).to eq(400)

      post "/moderate/editors-picks/pick.json", params: { topic_id: topic.id, reason: "a" * 1001 }
      expect(response.status).to eq(400)

      expect(topic.reload.tags.map(&:name)).not_to include("editors-pick")
    end

    it "rejects picking twice" do
      post "/moderate/editors-picks/pick.json", params: { topic_id: topic.id }
      post "/moderate/editors-picks/pick.json", params: { topic_id: topic.id }

      expect(response.status).to eq(422)
    end

    it "rejects topics outside the critique category" do
      other = Fabricate(:topic, user: engaged_poster)
      Fabricate(:post, topic: other, user: engaged_poster)

      post "/moderate/editors-picks/pick.json", params: { topic_id: other.id }

      expect(response.status).to eq(404)
    end
  end
end
