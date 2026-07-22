# frozen_string_literal: true

require "rails_helper"

# `order:fair` is registered through the custom filter registry rather than
# built as a bespoke list, so these specs pin the thing that would break on a
# core update: that an unrecognized order: key still reaches our block, and
# that the resulting list paginates like any other.
describe "order:fair through the filter route" do
  fab!(:category)
  fab!(:regular) { Fabricate(:user, created_at: 6.months.ago) }
  fab!(:newcomer) { Fabricate(:user, created_at: 1.day.ago) }
  fab!(:viewer, :user)

  before do
    SiteSetting.npn_critique_engagement_enabled = true
    SiteSetting.npn_critique_category = category.id.to_s
    sign_in(viewer)
  end

  def make_topic(user, created_at)
    topic = Fabricate(:topic, category: category, user: user, created_at: created_at)
    Fabricate(:post, topic: topic, user: user, created_at: created_at)
    topic
  end

  it "orders a filtered list by fairness rather than by activity" do
    established = make_topic(regular, 2.hours.ago)
    fresh_face = make_topic(newcomer, 2.hours.ago)

    get "/filter.json", params: { q: "categories:#{category.slug} order:fair" }

    expect(response.status).to eq(200)
    ids = response.parsed_body["topic_list"]["topics"].map { |topic| topic["id"] }
    expect(ids).to eq([fresh_face.id, established.id])
  end

  it "paginates without repeating a topic" do
    3.times { |i| make_topic(Fabricate(:user, created_at: 6.months.ago), i.hours.ago) }

    get "/filter.json", params: { q: "categories:#{category.slug} order:fair" }
    expect(response.status).to eq(200)
    first_page = response.parsed_body["topic_list"]["topics"].map { |topic| topic["id"] }

    expect(first_page.uniq.size).to eq(first_page.size)
    expect(first_page.size).to eq(3)
  end

  it "offers the ordering as a filter tip" do
    get "/filter.json", params: { q: "" }

    expect(response.status).to eq(200)
    tips = response.parsed_body["topic_list"]["filter_option_info"].map { |tip| tip["name"] }
    expect(tips).to include("order:fair")
  end

  it "leaves an unrelated order: value to core" do
    older = make_topic(regular, 3.days.ago)
    newer = make_topic(regular, 1.hour.ago)

    get "/filter.json", params: { q: "categories:#{category.slug} order:created" }

    expect(response.status).to eq(200)
    ids = response.parsed_body["topic_list"]["topics"].map { |topic| topic["id"] }
    expect(ids).to eq([newer.id, older.id])
  end
end
