# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The pick week's clock. Moderators judge a week of images once it closes,
  # so everything that says "this week" — the review queue's filter, the
  # dashboard board, the no-pick declarations — has to agree on when the week
  # turned over.
  #
  # Discourse runs in UTC, and a UTC Sunday starts at 5pm Saturday Pacific,
  # which put Saturday-evening posts in the wrong week. The boundary members
  # actually experience is Pacific midnight, so the week runs Sunday 00:00
  # Pacific to the next Sunday 00:00 Pacific. Resolving through the zone
  # rather than a fixed offset keeps that true across DST; the transitions
  # happen at 2am, so midnight is never ambiguous.
  module PickWeek
    extend self

    ZONE = "America/Los_Angeles"

    # The Sunday the current week began on, judged in Pacific.
    def current_start
      Time.find_zone!(ZONE).today.beginning_of_week(:sunday)
    end

    # The Sunday any given date's week began on.
    def start_of(date)
      date.beginning_of_week(:sunday)
    end

    # Pacific midnight opening the week — the cutoff for "since the week
    # began" queries.
    def cutoff(week_start)
      week_start.in_time_zone(ZONE)
    end

    # The week itself, half-open so the closing Sunday belongs to the next
    # week rather than to both.
    def range(week_start)
      cutoff(week_start)...cutoff(week_start + 7.days)
    end
  end
end
