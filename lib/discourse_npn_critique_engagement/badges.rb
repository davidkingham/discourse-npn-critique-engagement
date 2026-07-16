# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The three recognition badges. Names are site settings (staff are still
  # bikeshedding them); each badge is created on first grant if missing.
  module Badges
    GOLD = 1
    SILVER = 2
    BRONZE = 3

    def self.contributor
      ensure_badge(
        SiteSetting.npn_critique_contributor_badge_name,
        badge_type_id: BRONZE,
        multiple_grant: true,
        icon: "medal",
        description_key: "contributor_description",
      )
    end

    def self.supporter
      ensure_badge(
        SiteSetting.npn_critique_supporter_badge_name,
        badge_type_id: SILVER,
        multiple_grant: true,
        icon: "award",
        description_key: "supporter_description",
      )
    end

    def self.pillar
      ensure_badge(
        SiteSetting.npn_critique_pillar_badge_name,
        badge_type_id: GOLD,
        multiple_grant: false,
        icon: "trophy",
        description_key: "pillar_description",
      )
    end

    def self.rising
      ensure_badge(
        SiteSetting.npn_critique_rising_badge_name,
        badge_type_id: BRONZE,
        multiple_grant: false,
        icon: "seedling",
        description_key: "rising_description",
      )
    end

    def self.ensure_badge(name, badge_type_id:, multiple_grant:, icon:, description_key:)
      Badge.find_by(name: name) ||
        Badge.create!(
          name: name,
          badge_type_id: badge_type_id,
          multiple_grant: multiple_grant,
          icon: icon,
          description: I18n.t("npn_critique_engagement.badges.#{description_key}"),
          badge_grouping_id: BadgeGrouping::Community,
          listable: true,
          show_posts: false,
          system: false,
        )
    end
  end
end
