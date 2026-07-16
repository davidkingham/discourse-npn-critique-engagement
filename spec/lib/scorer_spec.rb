# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::Scorer do
  fab!(:category)
  fab!(:critic) { Fabricate(:user, created_at: 3.months.ago) }
  fab!(:poster) { Fabricate(:user, created_at: 3.months.ago) }

  let(:period_start) { Time.zone.today.beginning_of_month }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = category.id.to_s
  end

  def make_topic(user)
    topic = Fabricate(:topic, category: category, user: user)
    Fabricate(:post, topic: topic, user: user)
    topic
  end

  def reply(topic, user, length:, likes: 0, raw: nil)
    Fabricate(
      :post,
      topic: topic,
      user: user,
      raw: raw || ("critique " * 100)[0, length],
      like_count: likes,
    )
  end

  it "weights critiques by length, likes, and follow-up position" do
    topic_one = make_topic(poster)
    reply(topic_one, critic, length: 150) # first substantive reply: 1.0
    reply(topic_one, critic, length: 350) # follow-up: 1.5 × 0.3
    reply(topic_one, critic, length: 900) # follow-up: 2.0 × 0.3
    reply(topic_one, critic, length: 150) # beyond the follow-up cap: 0

    topic_two = make_topic(poster)
    reply(topic_two, critic, length: 150, likes: 10) # 1.0 + like bonus capped at 1.0

    described_class.run(period_start)

    row = DiscourseNpnCritiqueEngagement::Score.find_by(user_id: critic.id)
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

    described_class.run(period_start)

    row = DiscourseNpnCritiqueEngagement::Score.find_by(user_id: critic.id)
    expect(row.weighted_replies).to eq(0)
    expect(row.created_topics).to eq(1)
  end

  it "counts activity in subcategories of the critique category" do
    subcategory = Fabricate(:category, parent_category: category)
    topic = Fabricate(:topic, category: subcategory, user: poster)
    Fabricate(:post, topic: topic, user: poster)
    reply(topic, critic, length: 150)

    described_class.run(period_start)

    row = DiscourseNpnCritiqueEngagement::Score.find_by(user_id: critic.id)
    expect(row.weighted_replies).to eq(1.0)
    expect(DiscourseNpnCritiqueEngagement::Score.find_by(user_id: poster.id).created_topics).to eq(
      1,
    )
  end

  it "computes ratio and tiers members who post without reciprocating" do
    6.times { make_topic(poster) }

    described_class.run(period_start)

    row = DiscourseNpnCritiqueEngagement::Score.find_by(user_id: poster.id)
    expect(row.created_topics).to eq(6)
    expect(row.ratio).to eq(0)
    expect(row.tier).to eq("priority_outreach")
  end

  it "leaves finalized rows untouched and removes stale unfinalized rows" do
    inactive = Fabricate(:user, created_at: 3.months.ago)
    finalized =
      DiscourseNpnCritiqueEngagement::Score.create!(
        user_id: critic.id,
        period_start: period_start,
        score: 999,
        tier: :excellent,
        finalized: true,
        computed_at: 1.day.ago,
      )
    stale =
      DiscourseNpnCritiqueEngagement::Score.create!(
        user_id: inactive.id,
        period_start: period_start,
        score: 5,
        tier: :watch,
        finalized: false,
        computed_at: 1.day.ago,
      )
    topic = make_topic(poster)
    reply(topic, critic, length: 150)

    described_class.run(period_start)

    expect(finalized.reload.score).to eq(999)
    expect(DiscourseNpnCritiqueEngagement::Score.exists?(stale.id)).to eq(false)
  end

  it "does nothing when no category is configured" do
    SiteSetting.npn_critique_category = ""
    make_topic(poster)

    expect { described_class.run(period_start) }.not_to change(
      DiscourseNpnCritiqueEngagement::Score,
      :count,
    )
  end
end
