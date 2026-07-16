# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Who currently wears a recognition chip, cached for the post serializer's
  # hot path. Levels: "steward" (permanent badge holders), "guide" (currently
  # Excellent in the rolling window), and "contributor" (currently Healthy —
  # only when npn_critique_chip_min_tier includes it). Rebuilt after every
  # nightly score run, at monthly recognition, and on relevant setting
  # changes; positive signals only, so caching liberally is safe.
  module Recognition
    extend self

    def level_for(user_id)
      return nil if user_id.nil?
      map[user_id.to_s]
    end

    def rebuild!
      cache["map"] = build_map
    end

    def map
      cache["map"] || rebuild!
    end

    private

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

      steward_badge = Badge.find_by(name: SiteSetting.npn_critique_pillar_badge_name)
      if steward_badge
        UserBadge
          .where(badge_id: steward_badge.id)
          .pluck(:user_id)
          .each { |user_id| result[user_id.to_s] = "steward" }
      end

      result
    end
  end
end
