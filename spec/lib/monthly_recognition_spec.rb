# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::MonthlyRecognition do
  fab!(:category)
  fab!(:star_critic) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:casual_critic) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:poster) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:rising_star) { Fabricate(:user, created_at: 20.days.ago) }
  fab!(:guide_group, :group)
  fab!(:steward_group, :group)

  let(:last_month) { 1.month.ago.beginning_of_month.to_date }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = category.id.to_s
    # Tier boundaries are settings, so tests reach Excellent with a handful of
    # posts instead of prototype-scale volume.
    SiteSetting.npn_critique_excellent_score = 120
    SiteSetting.npn_critique_healthy_score = 60
    SiteSetting.npn_critique_badges_enabled = true
    SiteSetting.npn_critique_pillar_required_months = 1
    SiteSetting.npn_critique_supporter_flair_group = guide_group.id.to_s
    SiteSetting.npn_critique_pillar_flair_group = steward_group.id.to_s
    SiteSetting.npn_critique_season_topic_enabled = true

    3.times do
      topic = Fabricate(:topic, category: category, user: poster)
      Fabricate(:post, topic: topic, user: poster)
      Fabricate(:post, topic: topic, user: star_critic, raw: "critique " * 20)
    end
    extra_topic = Fabricate(:topic, category: category, user: poster)
    Fabricate(:post, topic: extra_topic, user: poster)
    Fabricate(:post, topic: extra_topic, user: casual_critic, raw: "critique " * 20)
    Fabricate(:post, topic: extra_topic, user: rising_star, raw: "critique " * 20)

    # The nightly job has been running since before the month ended.
    PluginStore.set(
      DiscourseNpnCritiqueEngagement::PLUGIN_NAME,
      DiscourseNpnCritiqueEngagement::Scorer::FIRST_RUN_KEY,
      2.months.ago.iso8601,
    )
    DiscourseNpnCritiqueEngagement::Scorer.run
  end

  def snapshot_for(user)
    DiscourseNpnCritiqueEngagement::MonthlySnapshot.find_by(
      user_id: user.id,
      snapshot_month: last_month,
    )
  end

  it "records the rolling standing as the month's snapshot without touching it" do
    described_class.record_due

    expect(snapshot_for(star_critic).tier).to eq("excellent")
    expect(snapshot_for(casual_critic).tier).to eq("healthy")
    expect(DiscourseNpnCritiqueEngagement::Score.find_by(user_id: star_critic.id)).to be_present
  end

  it "records each month only once" do
    described_class.record_due

    expect { described_class.record_due }.not_to change(
      DiscourseNpnCritiqueEngagement::MonthlySnapshot,
      :count,
    )
  end

  it "skips months that ended before the plugin started watching" do
    PluginStore.set(
      DiscourseNpnCritiqueEngagement::PLUGIN_NAME,
      DiscourseNpnCritiqueEngagement::Scorer::FIRST_RUN_KEY,
      Time.zone.now.iso8601,
    )

    expect { described_class.record_due }.not_to change(
      DiscourseNpnCritiqueEngagement::MonthlySnapshot,
      :count,
    )
  end

  it "grants contributor, guide, and steward badges at the configured thresholds" do
    described_class.record_due

    contributor = Badge.find_by(name: SiteSetting.npn_critique_contributor_badge_name)
    guide = Badge.find_by(name: SiteSetting.npn_critique_supporter_badge_name)
    steward = Badge.find_by(name: SiteSetting.npn_critique_pillar_badge_name)

    expect(UserBadge.where(badge: contributor).pluck(:user_id)).to contain_exactly(
      star_critic.id,
      casual_critic.id,
    )
    expect(UserBadge.where(badge: guide).pluck(:user_id)).to contain_exactly(star_critic.id)
    expect(UserBadge.where(badge: steward).pluck(:user_id)).to contain_exactly(star_critic.id)
  end

  it "syncs the flair groups, replacing guides and never removing stewards" do
    stale_member = Fabricate(:user)
    guide_group.add(stale_member)
    steward_group.add(stale_member)

    described_class.record_due

    expect(guide_group.reload.users).to contain_exactly(star_critic)
    expect(steward_group.reload.users).to contain_exactly(stale_member, star_critic)
  end

  describe "rising critic" do
    before do
      SiteSetting.npn_critique_rising_enabled = true
      SiteSetting.npn_critique_rising_min_weighted = 1.0
    end

    def rising_badge
      Badge.find_by(name: SiteSetting.npn_critique_rising_badge_name)
    end

    it "spotlights the most generous new critic and remembers them for the chip" do
      described_class.record_due

      expect(UserBadge.where(badge: rising_badge).pluck(:user_id)).to contain_exactly(
        rising_star.id,
      )
      stored =
        PluginStore.get(
          DiscourseNpnCritiqueEngagement::PLUGIN_NAME,
          described_class::RISING_CRITIC_KEY,
        )
      expect(stored["user_id"]).to eq(rising_star.id)
      expect(stored["month"]).to eq(last_month.to_s)
    end

    it "sends the winner a congratulations PM" do
      described_class.record_due

      pm =
        Topic
          .private_messages
          .joins(:topic_allowed_users)
          .where(topic_allowed_users: { user_id: rising_star.id })
          .order(created_at: :desc)
          .first
      expect(pm).to be_present
      expect(pm.first_post.raw).to include(SiteSetting.npn_critique_rising_badge_name)
      expect(pm.first_post.raw).to include(last_month.strftime("%B %Y"))
    end

    it "mentions the rising critic in the highlights topic" do
      described_class.record_due

      topic = Topic.where(category_id: category.id).order(created_at: :desc).first
      expect(topic.first_post.raw).to include("Rising critic of the month")
      expect(topic.first_post.raw).to include("@#{rising_star.username}")
    end

    it "never awards the same member twice" do
      BadgeGranter.grant(DiscourseNpnCritiqueEngagement::Badges.rising, rising_star)

      expect { described_class.record_due }.not_to change(
        UserBadge.where(badge: rising_badge),
        :count,
      )
    end

    it "awards nobody when no new member clears the bar" do
      SiteSetting.npn_critique_rising_min_weighted = 50.0

      described_class.record_due

      expect(UserBadge.where(badge: rising_badge).count).to eq(0)
    end
  end

  it "showcases the month's most awarded critiques in the highlights topic" do
    in_month = last_month + 10.days
    awarded_topic = Fabricate(:topic, category: category, user: poster, created_at: in_month)
    Fabricate(:post, topic: awarded_topic, user: poster, created_at: in_month)
    awarded_post =
      Fabricate(
        :post,
        topic: awarded_topic,
        user: star_critic,
        raw: "critique " * 20,
        created_at: in_month,
      )
    reaction =
      DiscourseReactions::Reaction.create!(
        post_id: awarded_post.id,
        reaction_value: "award-critique",
        reaction_type: :emoji,
      )
    DiscourseReactions::ReactionUser.create!(
      reaction_id: reaction.id,
      user_id: poster.id,
      post_id: awarded_post.id,
    )

    described_class.record_due

    topic = Topic.where(category_id: category.id).order(created_at: :desc).first
    expect(topic.first_post.raw).to include("Most awarded critiques")
    expect(topic.first_post.raw).to include(awarded_post.url)
  end

  it "posts a pinned highlights topic naming the top critics" do
    described_class.record_due

    topic = Topic.where(category_id: category.id).order(created_at: :desc).first
    expect(topic.title).to include(last_month.strftime("%B %Y"))
    expect(topic.pinned_until).to be_present
    expect(topic.first_post.raw).to include("@#{star_critic.username}")
  end
end
