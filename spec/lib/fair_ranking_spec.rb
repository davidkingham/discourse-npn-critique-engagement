# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::FairRanking do
  fab!(:category)
  fab!(:other_category, :category)
  fab!(:poster) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:critic) { Fabricate(:user, created_at: 6.months.ago) }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = category.id.to_s
  end

  def make_topic(user: poster, category: self.category, created_at: Time.zone.now, title: nil)
    topic =
      Fabricate(
        :topic,
        category: category,
        user: user,
        created_at: created_at,
        **(title ? { title: title } : {}),
      )
    Fabricate(:post, topic: topic, user: user, created_at: created_at)
    topic
  end

  # Comfortably over npn_critique_min_reply_length once quotes are stripped.
  def critique_text(length = 200)
    ("The light on the ridge carries this frame, though the horizon sits high. " * 20)[0, length]
  end

  def substantive_reply(topic, user = critic)
    Fabricate(:post, topic: topic, user: user, raw: critique_text)
  end

  def set_score(user, value)
    DiscourseNpnCritiqueEngagement::Score.create!(
      user_id: user.id,
      score: value,
      tier: :watch,
      computed_at: Time.zone.now,
    )
  end

  describe ".candidates" do
    it "returns topics with no substantive reply and drops the ones that have one" do
      waiting = make_topic
      answered = make_topic
      substantive_reply(answered)

      expect(described_class.candidates.pluck(:id)).to contain_exactly(waiting.id)
    end

    it "ignores replies that are too short and the poster's own replies" do
      topic = make_topic
      Fabricate(:post, topic: topic, user: critic, raw: "Lovely shot, well done.")
      Fabricate(:post, topic: topic, user: poster, raw: critique_text)

      expect(described_class.candidates.pluck(:id)).to include(topic.id)
    end

    it "does not count quoted text towards the length threshold" do
      topic = make_topic
      Fabricate(
        :post,
        topic: topic,
        user: critic,
        raw: "[quote=\"someone\"]#{critique_text(300)}[/quote] Agreed, thank you.",
      )

      expect(described_class.candidates.pluck(:id)).to include(topic.id)
    end

    it "stays inside the critique category tree" do
      make_topic(category: other_category)
      mine = make_topic

      expect(described_class.candidates.pluck(:id)).to contain_exactly(mine.id)
    end

    it "excludes weekly challenge announcements, excluded tags, and excluded title prefixes" do
      announcement = make_topic
      announcement.upsert_custom_fields(npn_weekly_challenge_slug: "spring")

      tagged = make_topic
      tagged.tags = [Fabricate(:tag, name: "no-critique")]
      SiteSetting.npn_critique_coverage_excluded_tags = "no-critique"

      make_topic(title: "Weekly Challenge: reflections in still water")
      SiteSetting.npn_critique_coverage_excluded_title_prefixes = "Weekly Challenge:"

      waiting = make_topic

      expect(described_class.candidates.pluck(:id)).to contain_exactly(waiting.id)
    end

    it "returns nothing when no critique category is configured" do
      make_topic
      SiteSetting.npn_critique_category = ""

      expect(described_class.candidates.pluck(:id)).to be_empty
    end
  end

  describe ".order_fair" do
    it "gives every author their best topic before anyone gets a second" do
      other = Fabricate(:user, created_at: 6.months.ago)
      poster_older = make_topic(created_at: 3.days.ago)
      poster_newer = make_topic(created_at: 1.hour.ago)
      other_topic = make_topic(user: other, created_at: 2.days.ago)

      ordered = described_class.order_fair(described_class.candidates).pluck(:id)

      # Whichever of poster's two ranks first, the other author is never
      # pushed below both of them.
      expect(ordered.index(other_topic.id)).to be <
        ordered.index([poster_older.id, poster_newer.id].max_by { |id| ordered.index(id) })
      expect(ordered).to contain_exactly(poster_older.id, poster_newer.id, other_topic.id)
    end

    it "ranks a new member's work above an established member's, all else equal" do
      newcomer = Fabricate(:user, created_at: 1.day.ago)
      established = make_topic(created_at: 2.hours.ago)
      fresh_face = make_topic(user: newcomer, created_at: 2.hours.ago)

      ordered = described_class.order_fair(described_class.candidates).pluck(:id)

      expect(ordered.first).to eq(fresh_face.id)
      expect(ordered.last).to eq(established.id)
    end

    it "lifts a topic the longer it waits without a critique" do
      recent = make_topic(created_at: 1.hour.ago)
      neglected =
        make_topic(user: Fabricate(:user, created_at: 6.months.ago), created_at: 9.days.ago)

      ordered = described_class.order_fair(described_class.candidates).pluck(:id)

      expect(ordered).to eq([neglected.id, recent.id])
    end

    it "moves a low-standing member down but never below the floor" do
      generous = Fabricate(:user, created_at: 6.months.ago)
      stingy = Fabricate(:user, created_at: 6.months.ago)
      set_score(generous, 200.0)
      set_score(stingy, -5_000.0)

      good = make_topic(user: generous, created_at: 2.hours.ago)
      bad = make_topic(user: stingy, created_at: 2.hours.ago)
      # Old enough that its waiting boost alone clears the floored penalty.
      old_and_stingy = make_topic(user: stingy, created_at: 12.days.ago)

      ordered = described_class.order_fair(described_class.candidates).pluck(:id)

      expect(ordered.index(good.id)).to be < ordered.index(bad.id)
      # Burial would put both of the stingy member's topics last; the floor
      # means the neglected one still outranks a fresh well-standing post.
      expect(ordered.index(old_and_stingy.id)).to be < ordered.index(bad.id)
    end

    it "is stable between identical requests" do
      3.times do |i|
        make_topic(user: Fabricate(:user, created_at: 6.months.ago), created_at: i.hours.ago)
      end

      first = described_class.order_fair(described_class.candidates).pluck(:id)
      second = described_class.order_fair(described_class.candidates).pluck(:id)

      expect(first).to eq(second)
    end

    it "paginates without dropping or repeating topics" do
      5.times do |i|
        make_topic(user: Fabricate(:user, created_at: 6.months.ago), created_at: i.hours.ago)
      end

      scope = described_class.order_fair(described_class.candidates)
      page_one = scope.limit(2).pluck(:id)
      page_two = scope.limit(2).offset(2).pluck(:id)

      expect(page_one & page_two).to be_empty
      expect((page_one + page_two).uniq.size).to eq(4)
    end
  end
end
