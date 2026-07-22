# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::FairFeedController do
  fab!(:critique_category) { Fabricate(:category, name: "Image Critiques") }
  fab!(:new_member_category) { Fabricate(:category, name: "New Members") }
  fab!(:discussion_category) { Fabricate(:category, name: "Discussions") }
  fab!(:regular) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:viewer) { Fabricate(:user, created_at: 6.months.ago) }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_fair_feed_enabled = true
    SiteSetting.npn_critique_category = critique_category.id.to_s
    SiteSetting.npn_critique_new_member_category = new_member_category.id.to_s
  end

  def make_topic(category, user = regular, created_at: 1.hour.ago)
    topic = Fabricate(:topic, category: category, user: user, created_at: created_at)
    Fabricate(:post, topic: topic, user: user, created_at: created_at)
    topic
  end

  # A finalized editors' pick: the pick tag plus a note carrying the declared
  # genre, the way EditorsPick.finalize! records it.
  def tag(name)
    Tag.find_or_create_by!(name: name)
  end

  def make_pick(genre, created_at: 1.hour.ago)
    topic = make_topic(critique_category, created_at: created_at)
    topic.tags = [tag("editors-pick")]
    note =
      topic.add_moderator_post(
        Discourse.system_user,
        "great work",
        post_type: Post.types[:small_action],
        action_code: DiscourseNpnCritiqueEngagement::EditorsPick::ACTION_CODE,
      )
    note.custom_fields[DiscourseNpnCritiqueEngagement::EditorsPick::GENRE_FIELD] = genre
    note.save_custom_fields
    topic
  end

  def pick_topics
    lane("npn_picks")["topic_list"]["topics"]
  end

  def lanes
    response.parsed_body["lanes"]
  end

  def lane(name)
    lanes.find { |candidate| candidate["name"] == name }
  end

  def topic_ids(name)
    lane(name)["topic_list"]["topics"].map { |topic| topic["id"] }
  end

  context "when signed in" do
    before { sign_in(viewer) }

    it "returns each lane with the layout it should render as" do
      make_topic(critique_category)
      make_topic(discussion_category)
      make_pick("birds")

      get "/critique-engagement/feed.json"

      expect(response.status).to eq(200)
      layouts = lanes.to_h { |entry| [entry["name"], entry["layout"]] }
      expect(layouts["npn_picks"]).to eq("carousel")
      expect(layouts["npn_waiting"]).to eq("justified")
      expect(layouts["npn_conversation"]).to eq("rows")
    end

    describe "the editors' picks carousel" do
      it "shows one pick per genre, most recent genre first, each labeled" do
        make_pick("birds", created_at: 3.hours.ago)
        make_pick("landscape", created_at: 1.hour.ago)

        get "/critique-engagement/feed.json"

        genres = pick_topics.map { |topic| topic["npn_pick_genre"] }
        expect(genres).to eq(%w[landscape birds])
      end

      it "collapses several picks in one genre down to the most recent" do
        make_pick("birds", created_at: 5.hours.ago)
        newest_bird = make_pick("birds", created_at: 1.hour.ago)

        get "/critique-engagement/feed.json"

        expect(pick_topics.map { |topic| topic["id"] }).to eq([newest_bird.id])
        expect(pick_topics.first["npn_pick_genre"]).to eq("birds")
      end

      it "falls back to a topic's genre tag when the pick declared none" do
        topic = make_topic(critique_category)
        topic.tags = [tag("editors-pick"), tag("macro")]

        get "/critique-engagement/feed.json"

        expect(pick_topics.first["npn_pick_genre"]).to eq("macro")
      end

      it "drops the lane when nothing has been picked" do
        make_topic(critique_category)

        get "/critique-engagement/feed.json"

        expect(lanes.map { |entry| entry["name"] }).not_to include("npn_picks")
      end
    end

    it "drops a lane entirely rather than returning it empty" do
      make_topic(critique_category)

      get "/critique-engagement/feed.json"

      expect(response.status).to eq(200)
      expect(lanes.map { |entry| entry["name"] }).to include("npn_waiting")
      expect(lanes.map { |entry| entry["name"] }).not_to include("npn_conversation")
    end

    it "keeps the conversation lane's slots however much the critique category posts" do
      discussion = make_topic(discussion_category)
      30.times { make_topic(critique_category, Fabricate(:user, created_at: 6.months.ago)) }

      get "/critique-engagement/feed.json"

      expect(topic_ids("npn_conversation")).to eq([discussion.id])
    end

    it "never puts a critique topic in the conversation lane" do
      critique = make_topic(critique_category)
      make_topic(discussion_category)

      get "/critique-engagement/feed.json"

      expect(topic_ids("npn_conversation")).not_to include(critique.id)
    end

    it "caps the waiting lane at the configured size" do
      SiteSetting.npn_fair_feed_waiting_limit = 3
      6.times { make_topic(critique_category, Fabricate(:user, created_at: 6.months.ago)) }

      get "/critique-engagement/feed.json"

      expect(topic_ids("npn_waiting").size).to eq(3)
    end

    it "omits stale topics beyond the freshness floor" do
      SiteSetting.npn_fair_feed_freshness_days = 7
      make_topic(discussion_category, created_at: 30.days.ago)

      get "/critique-engagement/feed.json"

      expect(lanes.map { |entry| entry["name"] }).not_to include("npn_conversation")
    end

    it "shows work only from photographers the viewer has never replied to" do
      met = Fabricate(:user, created_at: 6.months.ago)
      stranger = Fabricate(:user, created_at: 6.months.ago)

      already_met = make_topic(critique_category, met)
      Fabricate(:post, topic: already_met, user: viewer, raw: "Thanks for sharing this one.")
      unmet_topic = make_topic(critique_category, stranger)

      get "/critique-engagement/feed.json"

      expect(topic_ids("npn_unmet")).to include(unmet_topic.id)
      expect(topic_ids("npn_unmet")).not_to include(already_met.id)
    end

    it "keeps the auto-generated category description topics out" do
      about = Fabricate(:topic, category: discussion_category, user: Discourse.system_user)
      Fabricate(:post, topic: about, user: Discourse.system_user)
      discussion_category.update!(topic_id: about.id)
      real = make_topic(discussion_category)

      get "/critique-engagement/feed.json"

      expect(topic_ids("npn_conversation")).to contain_exactly(real.id)
    end

    it "leaves out categories the viewer cannot see" do
      secret = Fabricate(:private_category, group: Fabricate(:group))
      hidden = make_topic(secret)
      visible = make_topic(discussion_category)

      get "/critique-engagement/feed.json"

      expect(topic_ids("npn_conversation")).to contain_exactly(visible.id)
      expect(topic_ids("npn_conversation")).not_to include(hidden.id)
    end

    it "serializes thumbnail dimensions so the client can reserve the box" do
      make_topic(critique_category)

      get "/critique-engagement/feed.json"

      # The key must be present even when a topic has no image, otherwise the
      # client has nothing to branch on and every lane risks layout shift.
      expect(lane("npn_waiting")["topic_list"]["topics"].first).to have_key("thumbnails")
    end
  end

  it "404s for anonymous visitors by default, so crawlers keep Latest" do
    make_topic(critique_category)

    get "/critique-engagement/feed.json"

    expect(response.status).to eq(404)
  end

  it "serves anonymous visitors once the setting allows it" do
    SiteSetting.npn_fair_feed_anonymous = true
    make_topic(critique_category)

    get "/critique-engagement/feed.json"

    expect(response.status).to eq(200)
    expect(lanes.map { |entry| entry["name"] }).not_to include("npn_unmet")
  end

  # HomepageHelper.resolve runs on every HTML render, so a mistake in the
  # modifier takes the whole site down rather than just the homepage.
  describe "taking over the homepage" do
    it "claims the homepage for signed-in members" do
      expect(HomepageHelper.resolve(nil, viewer)).to eq("custom")
    end

    it "leaves anonymous visitors on the crawlable default" do
      expect(HomepageHelper.resolve(nil, nil)).not_to eq("custom")
    end

    it "claims it for anonymous visitors once the setting allows it" do
      SiteSetting.npn_fair_feed_anonymous = true

      expect(HomepageHelper.resolve(nil, nil)).to eq("custom")
    end

    it "leaves the homepage alone when the feed is off" do
      SiteSetting.npn_fair_feed_enabled = false

      expect(HomepageHelper.resolve(nil, viewer)).not_to eq("custom")
    end

    it "still renders ordinary pages" do
      sign_in(viewer)

      get "/latest"

      expect(response.status).to eq(200)
    end
  end

  describe "restricted to a beta group" do
    fab!(:beta, :group)
    fab!(:tester) { Fabricate(:user, created_at: 6.months.ago) }

    before do
      beta.add(tester)
      SiteSetting.npn_fair_feed_allowed_groups = beta.id.to_s
    end

    it "gives the homepage and the feed to a member of the group" do
      expect(HomepageHelper.resolve(nil, tester)).to eq("custom")

      sign_in(tester)
      make_topic(critique_category)
      get "/critique-engagement/feed.json"

      expect(response.status).to eq(200)
    end

    it "leaves everyone outside the group on Latest, feed included" do
      expect(HomepageHelper.resolve(nil, viewer)).not_to eq("custom")

      sign_in(viewer)
      make_topic(critique_category)
      get "/critique-engagement/feed.json"

      expect(response.status).to eq(404)
    end

    it "excludes anonymous visitors even with the anonymous setting on" do
      SiteSetting.npn_fair_feed_anonymous = true

      expect(HomepageHelper.resolve(nil, nil)).not_to eq("custom")

      make_topic(critique_category)
      get "/critique-engagement/feed.json"

      expect(response.status).to eq(404)
    end
  end

  it "404s when the feed is switched off" do
    SiteSetting.npn_fair_feed_enabled = false
    sign_in(viewer)

    get "/critique-engagement/feed.json"

    expect(response.status).to eq(404)
  end
end
