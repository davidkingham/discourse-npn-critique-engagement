# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::DiscussionPrompt do
  fab!(:discussions) { Fabricate(:category, name: "Discussions") }

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_discussion_prompt_enabled = true
    SiteSetting.npn_discussion_prompt_category = discussions.id.to_s
    SiteSetting.npn_discussion_prompt_day = "monday"
    SiteSetting.npn_discussion_prompt_questions =
      "What's in your bag right now?|How do you know when an edit is finished?"
  end

  # A Wednesday whose Monday (2024-01-01) is the rotation epoch itself, so the
  # bank starts at its first question — the tests read straight down the bank.
  let(:today) { Date.new(2024, 1, 3) }

  def posted_topics
    Topic.where(category_id: discussions.id).where.not(id: discussions.topic_id)
  end

  it "posts the week's question into the discussion category" do
    topic = described_class.post_due(today: today)

    expect(topic).to be_present
    expect(topic.category_id).to eq(discussions.id)
    expect(topic.title).to eq("What's in your bag right now?")
    expect(topic.first_post.raw).to include("What's in your bag right now?")
  end

  it "posts at most once a week, even across many runs" do
    3.times { described_class.post_due(today: today) }

    expect(posted_topics.count).to eq(1)
  end

  it "advances to the next question the following week, and cycles the bank" do
    week1 = described_class.post_due(today: today)
    week2 = described_class.post_due(today: today + 7)
    week3 = described_class.post_due(today: today + 14)

    expect([week1.title, week2.title]).to eq(
      ["What's in your bag right now?", "How do you know when an edit is finished?"],
    )
    # Two questions in the bank, so week three returns to the first.
    expect(week3.title).to start_with("What's in your bag right now?")
  end

  it "disambiguates a repeated question's title with its week" do
    described_class.post_due(today: today)
    third_week = described_class.post_due(today: today + 14)

    expect(third_week.title).to eq("What's in your bag right now? (Jan 15)")
  end

  it "pins the new question and unpins the previous one" do
    first = described_class.post_due(today: today)
    expect(first.reload.pinned_at).to be_present

    second = described_class.post_due(today: today + 7)

    expect(second.reload.pinned_at).to be_present
    expect(first.reload.pinned_at).to be_nil
  end

  it "leaves pinning alone when the setting is off" do
    SiteSetting.npn_discussion_prompt_pin = false

    topic = described_class.post_due(today: today)

    expect(topic.reload.pinned_at).to be_nil
  end

  it "uses a custom body template when one is set" do
    SiteSetting.npn_discussion_prompt_body = "This week: %{question} Reply below!"

    topic = described_class.post_due(today: today)

    expect(topic.first_post.raw).to eq("This week: What's in your bag right now? Reply below!")
  end

  it "does nothing when disabled, uncategorized, or the bank is empty" do
    SiteSetting.npn_discussion_prompt_enabled = false
    expect(described_class.post_due(today: today)).to be_nil

    SiteSetting.npn_discussion_prompt_enabled = true
    SiteSetting.npn_discussion_prompt_questions = ""
    expect(described_class.post_due(today: today)).to be_nil

    expect(posted_topics.count).to eq(0)
  end

  it "recovers from an invalid body template rather than raising" do
    SiteSetting.npn_discussion_prompt_body = "Bad %{nope} placeholder"

    topic = described_class.post_due(today: today)

    expect(topic).to be_present
    expect(topic.first_post.raw).to include("What's in your bag right now?")
  end
end
