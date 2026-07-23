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

  def make_image_topic(user, tag, created_at: nil)
    topic = Fabricate(:topic, category: category, user: user, tags: [tag])
    Fabricate(:post, topic: topic, user: user)
    topic.update!(created_at: created_at) if created_at
    topic
  end

  # The queue defaults to the last finished week, so list fixtures live there.
  def previous_week_time(offset = 0)
    (Date.current.beginning_of_week(:sunday) - 7).beginning_of_day + 12.hours + offset
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
    fab!(:engaged_topic) do
      make_image_topic(engaged_poster, landscape_tag, created_at: previous_week_time)
    end
    fab!(:quiet_topic) do
      make_image_topic(quiet_poster, landscape_tag, created_at: previous_week_time(1.minute))
    end
    fab!(:wildlife_topic) do
      make_image_topic(quiet_poster, wildlife_tag, created_at: previous_week_time(2.minutes))
    end

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

    it "defaults to the last finished week" do
      current_week_topic = make_image_topic(quiet_poster, landscape_tag)

      get "/moderate/editors-picks.json"

      expect(response.parsed_body["week_start"]).to eq(
        (Date.current.beginning_of_week(:sunday) - 7).to_s,
      )
      ids = response.parsed_body["topics"].map { |topic| topic["id"] }
      expect(ids).not_to include(current_week_topic.id)
      expect(ids).to include(engaged_topic.id)
    end

    it "filters by tag" do
      get "/moderate/editors-picks.json", params: { tag: "wildlife" }

      expect(response.parsed_body["topics"].map { |topic| topic["id"] }).to eq([wildlife_topic.id])
    end

    it "always offers every genre tag in the filter, even with no posts that week" do
      birds_tag = Fabricate(:tag, name: "birds")
      make_image_topic(quiet_poster, birds_tag, created_at: 3.weeks.ago)
      excluded_tag = Fabricate(:tag, name: "black-and-white")
      make_image_topic(quiet_poster, excluded_tag, created_at: previous_week_time(3.minutes))

      get "/moderate/editors-picks.json"

      expect(response.parsed_body["tags"]).to contain_exactly("birds", "landscape", "wildlife")
    end

    it "keeps weekly-challenge announcement topics out of the pick queue" do
      marked = make_image_topic(quiet_poster, landscape_tag, created_at: previous_week_time)
      marked.custom_fields["npn_weekly_challenge_slug"] = "geological-wonders"
      marked.save_custom_fields
      legacy =
        Fabricate(
          :topic,
          category: category,
          user: quiet_poster,
          title: "Weekly Challenge: Geological Wonders",
          created_at: previous_week_time,
        )
      Fabricate(:post, topic: legacy, user: quiet_poster)

      get "/moderate/editors-picks.json"

      ids = response.parsed_body["topics"].map { |topic| topic["id"] }
      expect(ids).not_to include(marked.id)
      expect(ids).not_to include(legacy.id)
      expect(ids).to include(engaged_topic.id)
    end

    it "excludes other weeks and other categories" do
      old_topic = make_image_topic(quiet_poster, landscape_tag, created_at: 3.weeks.ago)
      elsewhere = Fabricate(:topic, user: quiet_poster, tags: [landscape_tag])
      Fabricate(:post, topic: elsewhere, user: quiet_poster)

      get "/moderate/editors-picks.json"

      ids = response.parsed_body["topics"].map { |topic| topic["id"] }
      expect(ids).not_to include(old_topic.id)
      expect(ids).not_to include(elsewhere.id)
    end

    it "counts each poster's editors' picks from the last 12 months" do
      pick_tag = Fabricate(:tag, name: DiscourseNpnCritiqueEngagement::GenreTags.pick_tag)
      recent_pick = make_image_topic(engaged_poster, pick_tag)
      old_pick = make_image_topic(engaged_poster, pick_tag)
      # The pick tag's application time is when the pick was made, so backdate
      # topic_tags rather than the topics.
      TopicTag.where(topic_id: recent_pick.id).update_all(created_at: 2.months.ago)
      TopicTag.where(topic_id: old_pick.id).update_all(created_at: 13.months.ago)

      get "/moderate/editors-picks.json"

      topics = response.parsed_body["topics"].index_by { |topic| topic["id"] }
      expect(topics[engaged_topic.id]["recent_picks"]).to eq(1)
      expect(topics[quiet_topic.id]["recent_picks"]).to eq(0)
    end
  end

  describe "#pick" do
    fab!(:topic) { make_image_topic(engaged_poster, landscape_tag, created_at: previous_week_time) }

    before do
      sign_in(moderator)
      SiteSetting.npn_critique_pick_finalize_minutes = 0
    end

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

  describe "#no_pick" do
    before do
      sign_in(moderator)
      make_image_topic(engaged_poster, landscape_tag)
    end

    it "declares and undoes a deliberate no-pick for a genre" do
      post "/moderate/editors-picks/no-pick.json", params: { genre: "landscape" }

      expect(response.status).to eq(200)
      expect(response.parsed_body["username"]).to eq(moderator.username)
      expect(DiscourseNpnCritiqueEngagement::NoPick.where(genre: "landscape").count).to eq(1)

      # A second declaration keeps the original rather than duplicating it.
      post "/moderate/editors-picks/no-pick.json", params: { genre: "landscape" }
      expect(DiscourseNpnCritiqueEngagement::NoPick.where(genre: "landscape").count).to eq(1)

      delete "/moderate/editors-picks/no-pick.json", params: { genre: "landscape" }
      expect(response.status).to eq(204)
      expect(DiscourseNpnCritiqueEngagement::NoPick.exists?).to eq(false)
    end

    it "rejects a genre outside the vocabulary" do
      post "/moderate/editors-picks/no-pick.json", params: { genre: "not-a-genre" }

      expect(response.status).to eq(400)
    end
  end

  describe "#pick with an undo window" do
    fab!(:topic) { make_image_topic(engaged_poster, landscape_tag, created_at: previous_week_time) }

    before do
      sign_in(moderator)
      SiteSetting.npn_critique_pick_finalize_minutes = 10
    end

    def stage_pick
      post "/moderate/editors-picks/pick.json",
           params: {
             topic_id: topic.id,
             genre: "landscape",
             reason: "Lovely light.",
           }
      DiscourseNpnCritiqueEngagement::PendingPick.find_by(topic_id: topic.id)
    end

    it "stages the pick with nothing member-visible, shown as pending to staff" do
      pending = stage_pick

      expect(response.status).to eq(200)
      expect(response.parsed_body["pending"]["genre"]).to eq("landscape")
      expect(pending.reason).to eq("Lovely light.")
      expect(pending.finalize_at).to be_within(1.minute).of(10.minutes.from_now)

      expect(topic.reload.tags.map(&:name)).not_to include("editors-pick")
      expect(topic.posts.where(action_code: "npn_editors_pick")).to be_empty
      expect(UserBadge.count).to eq(0)
      expect(Topic.private_messages.count).to eq(0)

      get "/moderate/editors-picks.json"
      entry = response.parsed_body["topics"].find { |payload| payload["id"] == topic.id }
      expect(entry["pending"]["username"]).to eq(moderator.username)
      expect(entry["picked"]).to eq(false)
    end

    it "blocks a second pick while one is staged" do
      stage_pick

      post "/moderate/editors-picks/pick.json", params: { topic_id: topic.id }

      expect(response.status).to eq(422)
    end

    it "finalizes everything when the delayed job fires" do
      pending = stage_pick

      Jobs::NpnFinalizeEditorsPick.new.execute(pending_pick_id: pending.id)

      expect(topic.reload.tags.map(&:name)).to include("editors-pick")
      note = topic.posts.where(action_code: "npn_editors_pick").first
      expect(note.raw).to eq("Lovely light.")
      expect(note.custom_fields["npn_editors_pick_genre"]).to eq("landscape")
      expect(UserBadge.count).to eq(1)
      expect(Topic.private_messages.count).to eq(1)
      expect(DiscourseNpnCritiqueEngagement::PendingPick.exists?(topic_id: topic.id)).to eq(false)
    end

    it "undo cancels the staged pick and the job becomes a no-op" do
      pending = stage_pick

      post "/moderate/editors-picks/unpick.json", params: { topic_id: topic.id }

      expect(response.status).to eq(200)
      expect(DiscourseNpnCritiqueEngagement::PendingPick.exists?(topic_id: topic.id)).to eq(false)

      Jobs::NpnFinalizeEditorsPick.new.execute(pending_pick_id: pending.id)

      expect(topic.reload.tags.map(&:name)).not_to include("editors-pick")
      expect(Topic.private_messages.count).to eq(0)
    end

    it "the nightly sweep finalizes an overdue staged pick whose job was lost" do
      pending = stage_pick
      pending.update!(finalize_at: 1.minute.ago)

      DiscourseNpnCritiqueEngagement::EditorsPick.finalize_due!

      expect(topic.reload.tags.map(&:name)).to include("editors-pick")
      expect(DiscourseNpnCritiqueEngagement::PendingPick.exists?(topic_id: topic.id)).to eq(false)
    end
  end

  describe "#unpick on a finalized pick" do
    fab!(:topic) { make_image_topic(engaged_poster, landscape_tag, created_at: previous_week_time) }

    before do
      sign_in(moderator)
      SiteSetting.npn_critique_pick_finalize_minutes = 0
    end

    it "removes the tag, note, and badge — the PM stays" do
      post "/moderate/editors-picks/pick.json",
           params: {
             topic_id: topic.id,
             genre: "landscape",
             reason: "Lovely light.",
           }
      expect(topic.reload.tags.map(&:name)).to include("editors-pick")

      post "/moderate/editors-picks/unpick.json", params: { topic_id: topic.id }

      expect(response.status).to eq(200)
      expect(topic.reload.tags.map(&:name)).not_to include("editors-pick")
      expect(topic.posts.where(action_code: "npn_editors_pick", deleted_at: nil)).to be_empty
      expect(UserBadge.count).to eq(0)
      expect(Topic.private_messages.count).to eq(1)

      get "/moderate/editors-picks.json"
      entry = response.parsed_body["topics"].find { |payload| payload["id"] == topic.id }
      expect(entry["picked"]).to eq(false)
    end

    it "rejects unpicking a topic that isn't picked" do
      post "/moderate/editors-picks/unpick.json", params: { topic_id: topic.id }

      expect(response.status).to eq(422)
    end
  end
end
