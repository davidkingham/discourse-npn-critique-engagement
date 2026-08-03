# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Who currently wears a recognition chip, cached for the post serializer's
  # hot path. Levels: "steward" (permanent badge holders), "guide" (currently
  # Excellent in the rolling window), and "contributor" (currently Healthy —
  # only when npn_critique_chip_min_tier includes it). Also caches the public
  # give-and-take count (threads critiqued in the window, floored and banded),
  # the same way and for the same reason. Rebuilt after every nightly score run,
  # at monthly recognition, and on relevant setting changes; positive signals
  # only, so caching liberally is safe.
  module Recognition
    extend self

    # Bands the public give-and-take count is rounded down to, so the chip
    # celebrates a magnitude rather than publishing an exact figure that could
    # be divided into a member's (publicly countable) topic count. The
    # configured floor is always the lowest band.
    GIVEN_BANDS = [5, 10, 25, 50, 100, 250, 500].freeze

    def level_for(user_id)
      return nil if user_id.nil?
      map[user_id.to_s]
    end

    def given_count_for(user_id)
      return nil if user_id.nil?
      given_map[user_id.to_s]
    end

    def rebuild!
      cache["given"] = build_given_map
      cache["map"] = build_map
      nil
    end

    def map
      cached("map")
    end

    def given_map
      cached("given")
    end

    private

    # rebuild! populates every key at once, so a miss on any one of them warms
    # them all. Reading through this helper rather than relying on rebuild!'s
    # return value keeps the two caches independent of the order it fills them.
    def cached(key)
      cache[key] ||
        begin
          rebuild!
          cache[key]
        end
    end

    def cache
      @cache ||= DistributedCache.new("npn_critique_recognition")
    end

    # Keys are strings: DistributedCache round-trips through JSON on other
    # app processes, which would silently stringify integer keys anyway.
    def build_map
      result = {}

      if SiteSetting.npn_critique_chip_min_tier == "healthy"
        Score
          .where(tier: :healthy)
          .pluck(:user_id)
          .each { |user_id| result[user_id.to_s] = "contributor" }
      end

      Score
        .where(tier: :excellent)
        .pluck(:user_id)
        .each { |user_id| result[user_id.to_s] = "guide" }

      if (rising_user_id = current_rising_critic_id)
        result[rising_user_id.to_s] = "rising"
      end

      steward_badge = Badge.find_by(name: SiteSetting.npn_critique_pillar_badge_name)
      if steward_badge
        UserBadge
          .where(badge_id: steward_badge.id)
          .pluck(:user_id)
          .each { |user_id| result[user_id.to_s] = "steward" }
      end

      result
    end

    # Distinct threads critiqued in the rolling window, banded, for the public
    # give-and-take count. Only members at or above the floor are cached: a
    # count with no denominator can celebrate but never shame. Like build_map
    # this ignores whether the chip is currently switched on, so toggling the
    # setting takes effect immediately without a rebuild.
    def build_given_map
      floor = SiteSetting.npn_critique_given_chip_min_count

      Score
        .where(topics_replied: floor..)
        .pluck(:user_id, :topics_replied)
        .to_h { |user_id, count| [user_id.to_s, given_band(count, floor)] }
    end

    # The highest band the member has cleared, never below the floor they had
    # to clear to appear at all.
    def given_band(count, floor)
      GIVEN_BANDS.select { |band| band > floor && band <= count }.max || floor
    end

    # The rising critic's spotlight chip lasts exactly the month after the
    # win (July's winner wears it through August), then lapses on its own.
    def current_rising_critic_id
      return nil if !SiteSetting.npn_critique_rising_enabled

      stored = PluginStore.get(PLUGIN_NAME, MonthlyRecognition::RISING_CRITIC_KEY)
      return nil if stored.blank?

      won_month = Date.parse(stored["month"])
      stored["user_id"] if won_month.next_month == Date.current.beginning_of_month
    rescue Date::Error
      nil
    end
  end
end
