# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnCritiqueEngagement::PickWeek do
  # Sunday 03:00 UTC is still Saturday 8pm in Pacific, so the week has not
  # turned over yet — the whole reason this module exists.
  it "keeps the week open until Pacific midnight, not UTC midnight" do
    freeze_time(Time.utc(2026, 7, 26, 3, 0)) do
      expect(described_class.current_start).to eq(Date.new(2026, 7, 19))
    end

    freeze_time(Time.utc(2026, 7, 26, 7, 0)) do
      expect(described_class.current_start).to eq(Date.new(2026, 7, 26))
    end
  end

  it "opens the week at Pacific midnight through daylight saving and standard time" do
    expect(described_class.cutoff(Date.new(2026, 7, 26))).to eq(Time.utc(2026, 7, 26, 7, 0))
    expect(described_class.cutoff(Date.new(2026, 1, 11))).to eq(Time.utc(2026, 1, 11, 8, 0))
  end

  it "covers seven days and hands the closing Sunday to the next week" do
    range = described_class.range(Date.new(2026, 7, 19))

    expect(range).to cover(Time.utc(2026, 7, 19, 7, 0))
    expect(range).to cover(Time.utc(2026, 7, 26, 6, 59))
    expect(range).not_to cover(Time.utc(2026, 7, 19, 6, 59))
    expect(range).not_to cover(Time.utc(2026, 7, 26, 7, 0))
  end

  it "normalises any date to the Sunday its week began on" do
    expect(described_class.start_of(Date.new(2026, 7, 25))).to eq(Date.new(2026, 7, 19))
    expect(described_class.start_of(Date.new(2026, 7, 19))).to eq(Date.new(2026, 7, 19))
  end
end
