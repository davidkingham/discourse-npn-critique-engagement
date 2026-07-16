# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::SeasonCloser do
  fab!(:category)
  fab!(:star_critic) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:casual_critic) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:poster) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:supporter_group, :group)
  fab!(:pillar_group, :group)

  let(:last_month) { 1.month.ago.beginning_of_month }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = category.id.to_s
    # Tier boundaries are settings, so tests reach Excellent with a handful of
    # posts instead of prototype-scale volume.
    SiteSetting.npn_critique_excellent_score = 120
    SiteSetting.npn_critique_healthy_score = 60
    SiteSetting.npn_critique_badges_enabled = true
    SiteSetting.npn_critique_pillar_required_months = 1
    SiteSetting.npn_critique_supporter_flair_group = supporter_group.id.to_s
    SiteSetting.npn_critique_pillar_flair_group = pillar_group.id.to_s
    SiteSetting.npn_critique_season_topic_enabled = true

    freeze_time(last_month + 10.days) do
      3.times do
        topic = Fabricate(:topic, category: category, user: poster)
        Fabricate(:post, topic: topic, user: poster)
        Fabricate(:post, topic: topic, user: star_critic, raw: "critique " * 20)
      end
      extra_topic = Fabricate(:topic, category: category, user: poster)
      Fabricate(:post, topic: extra_topic, user: poster)
      Fabricate(:post, topic: extra_topic, user: casual_critic, raw: "critique " * 20)
    end

    # In production the nightly job populates the month as it happens; the
    # close is keyed off those unfinalized rows.
    DiscourseNpnCritiqueEngagement::Scorer.run(last_month)
  end

  def close!
    described_class.close_due
  end

  def score_for(user)
    DiscourseNpnCritiqueEngagement::Score.find_by(user_id: user.id, period_start: last_month)
  end

  it "freezes the month's rows" do
    close!

    expect(score_for(star_critic).finalized).to eq(true)
    expect(score_for(star_critic).tier).to eq("excellent")
    expect(score_for(casual_critic).tier).to eq("healthy")
  end

  it "grants contributor, supporter, and pillar badges at the configured thresholds" do
    close!

    contributor = Badge.find_by(name: SiteSetting.npn_critique_contributor_badge_name)
    supporter = Badge.find_by(name: SiteSetting.npn_critique_supporter_badge_name)
    pillar = Badge.find_by(name: SiteSetting.npn_critique_pillar_badge_name)

    expect(UserBadge.where(badge: contributor).pluck(:user_id)).to contain_exactly(
      star_critic.id,
      casual_critic.id,
    )
    expect(UserBadge.where(badge: supporter).pluck(:user_id)).to contain_exactly(star_critic.id)
    expect(UserBadge.where(badge: pillar).pluck(:user_id)).to contain_exactly(star_critic.id)
  end

  it "syncs the flair groups, replacing supporters and never removing pillars" do
    stale_member = Fabricate(:user)
    supporter_group.add(stale_member)
    pillar_group.add(stale_member)

    close!

    expect(supporter_group.reload.users).to contain_exactly(star_critic)
    expect(pillar_group.reload.users).to contain_exactly(stale_member, star_critic)
  end

  it "posts a pinned season-close topic naming the winners" do
    close!

    topic = Topic.where(category_id: category.id).order(created_at: :desc).first
    expect(topic.title).to include(last_month.strftime("%B %Y"))
    expect(topic.pinned_until).to be_present
    expect(topic.first_post.raw).to include("@#{star_critic.username}")
  end

  it "closes past months but leaves the running month open" do
    topic = Fabricate(:topic, category: category, user: poster)
    Fabricate(:post, topic: topic, user: poster)
    Fabricate(:post, topic: topic, user: star_critic, raw: "critique " * 20)
    DiscourseNpnCritiqueEngagement::Scorer.run

    close!

    current_period = Time.zone.today.beginning_of_month
    expect(
      DiscourseNpnCritiqueEngagement::Score.for_period(last_month).where(finalized: false),
    ).to be_empty
    expect(
      DiscourseNpnCritiqueEngagement::Score.for_period(current_period).where(finalized: false),
    ).not_to be_empty
    expect(DiscourseNpnCritiqueEngagement::Score.for_period(current_period).finalized).to be_empty
  end
end
