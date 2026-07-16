# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::Scorer do
  fab!(:category)
  fab!(:critic) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:poster) { Fabricate(:user, created_at: 6.months.ago) }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = category.id.to_s
  end

  def make_topic(user, category: nil, created_at: nil)
    topic =
      Fabricate(
        :topic,
        category: category || self.category,
        user: user,
        created_at: created_at || Time.zone.now,
      )
    Fabricate(:post, topic: topic, user: user, created_at: topic.created_at)
    topic
  end

  def reply(topic, user, length:, likes: 0, raw: nil, created_at: nil)
    Fabricate(
      :post,
      topic: topic,
      user: user,
      raw: raw || ("critique " * 100)[0, length],
      like_count: likes,
      created_at: created_at || Time.zone.now,
    )
  end

  def score_row(user)
    DiscourseNpnCritiqueEngagement::Score.find_by(user_id: user.id)
  end

  it "weights critiques by length, likes, and follow-up position" do
    topic_one = make_topic(poster)
    reply(topic_one, critic, length: 150) # first substantive reply: 1.0
    reply(topic_one, critic, length: 350) # follow-up: 1.5 × 0.3
    reply(topic_one, critic, length: 900) # follow-up: 2.0 × 0.3
    reply(topic_one, critic, length: 150) # beyond the follow-up cap: 0

    topic_two = make_topic(poster)
    reply(topic_two, critic, length: 150, likes: 10) # 1.0 + like bonus capped at 1.0

    described_class.run

    row = score_row(critic)
    expect(row.weighted_replies).to eq(4.05)
    expect(row.topics_replied).to eq(2)
    expect(row.created_topics).to eq(0)
    expect(row.ratio).to eq(2.0)
    expect(row.score).to be > 0
  end

  it "never counts deleted posts, whispers, self-replies, short replies, or quoted walls" do
    topic = make_topic(poster)

    reply(topic, critic, length: 50) # below the substance floor
    reply(topic, critic, length: 300, raw: "[quote=\"a\"]#{"q" * 500}[/quote] nice") # quotes stripped
    Fabricate(
      :post,
      topic: topic,
      user: critic,
      raw: "This whisper is a long staff aside that must never count. " * 6,
      post_type: Post.types[:whisper],
    )
    reply(topic, critic, length: 300).trash!

    own_topic = make_topic(critic)
    reply(own_topic, critic, length: 300) # self-reply

    described_class.run

    row = score_row(critic)
    expect(row.weighted_replies).to eq(0)
    expect(row.created_topics).to eq(1)
  end

  it "only counts activity inside the rolling window" do
    old_topic = make_topic(poster, created_at: 100.days.ago)
    reply(old_topic, critic, length: 300, created_at: 100.days.ago)
    recent_topic = make_topic(poster)
    reply(recent_topic, critic, length: 150)

    described_class.run

    row = score_row(critic)
    expect(row.weighted_replies).to eq(1.0)
    expect(score_row(poster).created_topics).to eq(1)
  end

  it "counts activity in subcategories of the critique category" do
    subcategory = Fabricate(:category, parent_category: category)
    topic = make_topic(poster, category: subcategory)
    reply(topic, critic, length: 150)

    described_class.run

    expect(score_row(critic).weighted_replies).to eq(1.0)
    expect(score_row(poster).created_topics).to eq(1)
  end

  describe "award reactions" do
    fab!(:voter) { Fabricate(:user, created_at: 6.months.ago) }

    def give_award(post, user, reaction_value)
      reaction =
        DiscourseReactions::Reaction.find_or_create_by!(
          post_id: post.id,
          reaction_value: reaction_value,
          reaction_type: :emoji,
        )
      DiscourseReactions::ReactionUser.create!(
        reaction_id: reaction.id,
        user_id: user.id,
        post_id: post.id,
      )
    end

    it "adds an award bonus, weighting the topic owner's award double" do
      topic = make_topic(poster)
      awarded = reply(topic, critic, length: 150)
      give_award(awarded, poster, "award-helped-my-work") # topic owner: 0.5 × 2
      give_award(awarded, voter, "award-critique") # 0.5

      described_class.run

      row = score_row(critic)
      expect(row.weighted_replies).to eq(2.5) # 1.0 base + 1.5 award bonus
      expect(row.awards_received).to eq(2)
    end

    it "caps the total award bonus per critique and counts legacy names" do
      topic = make_topic(poster)
      awarded = reply(topic, critic, length: 150)
      # Reactions allow one per member per post, so the cap is reached via
      # awards from distinct members.
      give_award(awarded, voter, "star2") # legacy name still counts
      3.times { give_award(awarded, Fabricate(:user), "award-critique") }

      described_class.run

      row = score_row(critic)
      expect(row.weighted_replies).to eq(2.5) # 4 × 0.5 = 2.0, capped at 1.5
      expect(row.awards_received).to eq(4)
    end

    it "ignores self-awards and non-award reactions" do
      topic = make_topic(poster)
      awarded = reply(topic, critic, length: 150)
      give_award(awarded, critic, "award-critique") # self-award
      give_award(awarded, voter, "clap") # not an award

      described_class.run

      row = score_row(critic)
      expect(row.weighted_replies).to eq(1.0)
      expect(row.awards_received).to eq(0)
    end

    it "is inert when the award reaction list is emptied" do
      SiteSetting.npn_critique_award_reactions = ""
      topic = make_topic(poster)
      awarded = reply(topic, critic, length: 150)
      give_award(awarded, voter, "award-critique")

      described_class.run

      expect(score_row(critic).weighted_replies).to eq(1.0)
    end
  end

  it "computes ratio and tiers members who post without reciprocating" do
    6.times { make_topic(poster) }

    described_class.run

    row = score_row(poster)
    expect(row.created_topics).to eq(6)
    expect(row.ratio).to eq(0)
    expect(row.tier).to eq("priority_outreach")
  end

  it "keeps one row per member and drops members whose window emptied" do
    stale =
      DiscourseNpnCritiqueEngagement::Score.create!(
        user_id: Fabricate(:user).id,
        score: 5,
        tier: :watch,
        computed_at: 1.day.ago,
      )
    topic = make_topic(poster)
    reply(topic, critic, length: 150)

    described_class.run
    described_class.run

    expect(DiscourseNpnCritiqueEngagement::Score.where(user_id: critic.id).count).to eq(1)
    expect(DiscourseNpnCritiqueEngagement::Score.exists?(stale.id)).to eq(false)
  end

  it "records when it first produced data" do
    make_topic(poster)

    expect(described_class.first_run_at).to be_nil
    described_class.run
    expect(described_class.first_run_at).to be_within(1.minute).of(Time.zone.now)
  end

  it "does nothing when no category is configured" do
    SiteSetting.npn_critique_category = ""
    make_topic(poster)

    expect { described_class.run }.not_to change(DiscourseNpnCritiqueEngagement::Score, :count)
  end
end
