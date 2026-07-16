# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::Formula do
  fab!(:established_user) { Fabricate(:user, created_at: 3.months.ago) }
  fab!(:new_user) { Fabricate(:user, created_at: 3.days.ago) }

  let(:period_start) { Time.zone.today.beginning_of_month }

  describe ".score" do
    it "rewards giving critiques and grows with weighted output" do
      low = described_class.score(weighted_replies: 2, created_topics: 1, topics_replied: 2)
      high = described_class.score(weighted_replies: 10, created_topics: 1, topics_replied: 10)

      expect(high).to be > low
      expect(low).to be > 0
    end

    it "goes negative for members posting many photos without reciprocating" do
      score = described_class.score(weighted_replies: 0, created_topics: 10, topics_replied: 0)

      expect(score).to be < SiteSetting.npn_critique_watch_floor_score
    end

    it "never penalizes pure repliers" do
      score = described_class.score(weighted_replies: 1, created_topics: 0, topics_replied: 1)

      expect(score).to be > 0
    end

    it "shrinks the below-1:1 penalty smoothly as the ratio improves" do
      worse = described_class.score(weighted_replies: 2, created_topics: 8, topics_replied: 2)
      better = described_class.score(weighted_replies: 2, created_topics: 8, topics_replied: 6)

      expect(better).to be > worse
    end

    it "gives grace-protected members a score floor regardless of activity" do
      score =
        described_class.score(
          weighted_replies: 0,
          created_topics: 2,
          topics_replied: 0,
          grace: true,
        )

      expect(score).to eq(described_class::GRACE_FLOOR)
    end
  end

  describe ".grace_protected?" do
    def grace_protected?(user:, created_topics: 0, topics_replied: 0)
      described_class.grace_protected?(
        user: user,
        period_start: period_start,
        created_topics: created_topics,
        topics_replied: topics_replied,
      )
    end

    it "protects new members while they find their feet" do
      expect(grace_protected?(user: new_user, created_topics: 2)).to eq(true)
    end

    it "withdraws protection from new members who immediately topic-dump" do
      expect(grace_protected?(user: new_user, created_topics: 3, topics_replied: 0)).to eq(false)
      expect(grace_protected?(user: new_user, created_topics: 3, topics_replied: 1)).to eq(true)
    end

    it "never applies to established members" do
      expect(grace_protected?(user: established_user)).to eq(false)
    end
  end

  describe ".tier_for" do
    def tier_for(user:, score:, created_topics: 0)
      described_class.tier_for(
        user: user,
        score: score,
        created_topics: created_topics,
        period_start: period_start,
      )
    end

    it "maps scores to tiers at the configured boundaries" do
      expect(tier_for(user: established_user, score: 400)).to eq(:excellent)
      expect(tier_for(user: established_user, score: 100)).to eq(:healthy)
      expect(tier_for(user: established_user, score: -100)).to eq(:watch)
    end

    it "splits below-floor members into priority outreach and low activity by topic count" do
      expect(tier_for(user: established_user, score: -101, created_topics: 6)).to eq(
        :priority_outreach,
      )
      expect(tier_for(user: established_user, score: -101, created_topics: 2)).to eq(:low_activity)
    end

    it "always labels members inside the grace window as new members" do
      expect(tier_for(user: new_user, score: -500, created_topics: 6)).to eq(:new_member)
      expect(tier_for(user: new_user, score: 500)).to eq(:new_member)
    end
  end

  describe ".critiques_to_reach" do
    it "returns how many additional critiques cross the target score" do
      current = described_class.score(weighted_replies: 1, created_topics: 2, topics_replied: 1)
      needed =
        described_class.critiques_to_reach(
          SiteSetting.npn_critique_healthy_score,
          weighted_replies: 1,
          created_topics: 2,
          topics_replied: 1,
        )

      expect(current).to be < SiteSetting.npn_critique_healthy_score
      expect(needed).to be_between(1, described_class::SIMULATION_LIMIT)

      simulated =
        described_class.score(
          weighted_replies: 1 + needed,
          created_topics: 2,
          topics_replied: 1 + needed,
        )
      expect(simulated).to be >= SiteSetting.npn_critique_healthy_score
    end

    it "returns nil when the target is out of simulated reach" do
      expect(
        described_class.critiques_to_reach(
          1_000_000,
          weighted_replies: 0,
          created_topics: 0,
          topics_replied: 0,
        ),
      ).to be_nil
    end
  end
end
