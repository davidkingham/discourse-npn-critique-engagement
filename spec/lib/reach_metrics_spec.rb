# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::ReachMetrics do
  fab!(:critique) { Fabricate(:category, name: "Image Critiques") }
  fab!(:discussions) { Fabricate(:category, name: "Discussions") }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = critique.id.to_s
    SiteSetting.npn_critique_min_reply_length = 100
  end

  def critique_text(length = 200)
    ("The light on the ridge carries this frame, though the horizon sits high. " * 20)[0, length]
  end

  def topic_in(category, user, created_at)
    topic = Fabricate(:topic, category: category, user: user, created_at: created_at)
    Fabricate(:post, topic: topic, user: user, created_at: created_at)
    topic
  end

  def critique_on(topic, critic, created_at:, raw: nil)
    Fabricate(:post, topic: topic, user: critic, raw: raw || critique_text, created_at: created_at)
  end

  # Everything happens inside one week so it lands in a single row.
  let(:when_posted) { 2.days.ago }

  def this_week
    described_class.weekly(weeks: 4).find { |row| row[:week] == Date.current.beginning_of_week }
  end

  it "returns nothing when no critique category is configured" do
    SiteSetting.npn_critique_category = ""
    expect(described_class.weekly).to eq([])
  end

  it "counts distinct members who received a substantive critique, not replies" do
    poster_a = Fabricate(:user)
    poster_b = Fabricate(:user)
    critic = Fabricate(:user)

    topic_a = topic_in(critique, poster_a, when_posted)
    topic_b = topic_in(critique, poster_b, when_posted)
    # Two critiques on A, one on B — three replies, two distinct members reached.
    critique_on(topic_a, critic, created_at: when_posted)
    critique_on(topic_a, Fabricate(:user), created_at: when_posted)
    critique_on(topic_b, critic, created_at: when_posted)

    expect(this_week[:distinct_replied_to]).to eq(2)
  end

  it "ignores short replies and the poster's own replies when counting reach" do
    poster = Fabricate(:user)
    topic = topic_in(critique, poster, when_posted)
    critique_on(topic, Fabricate(:user), created_at: when_posted, raw: "nice one, love it")
    critique_on(topic, poster, created_at: when_posted)

    expect(this_week[:distinct_replied_to]).to eq(0)
  end

  it "measures the share of topics answered within 48 hours by posting week" do
    fast = topic_in(critique, Fabricate(:user), when_posted)
    slow = topic_in(critique, Fabricate(:user), when_posted)

    critique_on(fast, Fabricate(:user), created_at: when_posted + 1.hour)
    critique_on(slow, Fabricate(:user), created_at: when_posted + 3.days)

    row = this_week
    expect(row[:topics_posted]).to eq(2)
    expect(row[:answered_within_48h]).to eq(1)
  end

  describe "reach beyond the active core" do
    it "counts critiques going to authors outside the top decile of givers" do
      # Twelve scored members; the single most generous is the core.
      members = Array.new(12) { |i| Fabricate(:user) }
      members.each_with_index do |member, i|
        DiscourseNpnCritiqueEngagement::Score.create!(
          user_id: member.id,
          weighted_replies: i.to_f, # member 11 is the top giver → the core
          score: 0,
          tier: :watch,
          computed_at: Time.zone.now,
        )
      end
      core = members.last
      outsider = members.first

      to_core = topic_in(critique, core, when_posted)
      to_outsider = topic_in(critique, outsider, when_posted)
      critique_on(to_core, Fabricate(:user), created_at: when_posted)
      critique_on(to_outsider, Fabricate(:user), created_at: when_posted)

      row = this_week
      expect(row[:critiques_given]).to eq(2)
      expect(row[:critiques_to_non_core]).to eq(1)
    end

    it "treats everyone as non-core until the community reaches ten scored members" do
      giver = Fabricate(:user)
      DiscourseNpnCritiqueEngagement::Score.create!(
        user_id: giver.id,
        weighted_replies: 999.0,
        score: 0,
        tier: :excellent,
        computed_at: Time.zone.now,
      )
      topic = topic_in(critique, giver, when_posted)
      critique_on(topic, Fabricate(:user), created_at: when_posted)

      expect(this_week[:critiques_to_non_core]).to eq(1)
    end
  end

  it "tracks topic and reply volume outside the critique tree" do
    author = Fabricate(:user)
    discussion = topic_in(discussions, author, when_posted)
    Fabricate(:post, topic: discussion, user: Fabricate(:user), created_at: when_posted)
    # A critique-category topic must not count towards non-critique volume.
    topic_in(critique, author, when_posted)

    row = this_week
    expect(row[:non_critique_topics]).to eq(1)
    expect(row[:non_critique_replies]).to eq(1)
  end

  it "buckets activity into the correct weeks" do
    poster = Fabricate(:user)
    this = topic_in(critique, poster, 2.days.ago)
    prior = topic_in(critique, Fabricate(:user), 9.days.ago)
    critique_on(this, Fabricate(:user), created_at: 2.days.ago)
    critique_on(prior, Fabricate(:user), created_at: 9.days.ago)

    weeks = described_class.weekly(weeks: 4)
    current = weeks.find { |row| row[:week] == Date.current.beginning_of_week }
    last = weeks.find { |row| row[:week] == 1.week.ago.to_date.beginning_of_week }

    expect(current[:distinct_replied_to]).to eq(1)
    expect(last[:distinct_replied_to]).to eq(1)
  end
end
