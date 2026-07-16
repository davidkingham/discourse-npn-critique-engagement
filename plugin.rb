# frozen_string_literal: true

# name: discourse-npn-critique-engagement
# about: Critique engagement scoring, recognition, and moderation tools for Nature Photographers Network.
# version: 0.1.0
# authors: David Kingham
# url: https://github.com/davidkingham/discourse-npn-critique-engagement
# license: MIT

enabled_site_setting :npn_critique_engagement_enabled

register_asset "stylesheets/npn-critique-engagement.scss"

register_svg_icon "medal"
register_svg_icon "award"
register_svg_icon "trophy"
register_svg_icon "ranking-star"
register_svg_icon "arrow-trend-up"
register_svg_icon "arrow-trend-down"
register_svg_icon "hand-holding-heart"
register_svg_icon "eye"
register_svg_icon "moon"
register_svg_icon "seedling"

module ::DiscourseNpnCritiqueEngagement
  PLUGIN_NAME = "discourse-npn-critique-engagement"
end

require_relative "lib/discourse_npn_critique_engagement/engine"

after_initialize do
  require_relative "lib/discourse_npn_critique_engagement/has_tier"
  require_relative "lib/discourse_npn_critique_engagement/formula"
  require_relative "lib/discourse_npn_critique_engagement/scorer"
  require_relative "lib/discourse_npn_critique_engagement/badges"
  require_relative "lib/discourse_npn_critique_engagement/recognition"
  require_relative "lib/discourse_npn_critique_engagement/monthly_recognition"
  require_relative "app/models/discourse_npn_critique_engagement/score"
  require_relative "app/models/discourse_npn_critique_engagement/monthly_snapshot"
  require_relative "app/models/discourse_npn_critique_engagement/outreach_log"
  require_relative "app/serializers/discourse_npn_critique_engagement/leaderboard_entry_serializer"
  require_relative "app/serializers/discourse_npn_critique_engagement/impact_row_serializer"
  require_relative "app/serializers/discourse_npn_critique_engagement/snapshot_row_serializer"
  require_relative "app/serializers/discourse_npn_critique_engagement/outreach_log_serializer"
  require_relative "app/serializers/discourse_npn_critique_engagement/report_row_serializer"
  require_relative "app/controllers/discourse_npn_critique_engagement/leaderboards_controller"
  require_relative "app/controllers/discourse_npn_critique_engagement/impact_controller"
  require_relative "app/controllers/discourse_npn_critique_engagement/admin/reports_controller"
  require_relative "app/controllers/discourse_npn_critique_engagement/admin/outreach_controller"
  require_relative "app/jobs/scheduled/npn_critique_scores_refresh"

  add_admin_route "npn_critique_engagement.title",
                  "discourse-npn-critique-engagement",
                  use_new_show_route: true

  # Staff surface: tier and score on the user card, anywhere on the forum.
  # Negative signals never leave staff view.
  add_to_serializer(
    :user_card,
    :npn_critique_engagement,
    include_condition: -> { SiteSetting.npn_critique_engagement_enabled && scope.is_staff? },
  ) do
    row = DiscourseNpnCritiqueEngagement::Score.current_for(object)
    row && { score: row.score.round, tier: row.tier }
  end

  # Public recognition chips: positive signals only, rendered next to poster
  # names and on the user card. Backed by a cache so the post serializer's
  # hot path stays a hash lookup.
  add_to_serializer(
    :post,
    :npn_critique_recognition,
    include_condition: -> do
      SiteSetting.npn_critique_engagement_enabled && SiteSetting.npn_critique_chips_enabled &&
        DiscourseNpnCritiqueEngagement::Recognition.level_for(object.user_id).present?
    end,
  ) { DiscourseNpnCritiqueEngagement::Recognition.level_for(object.user_id) }

  add_to_serializer(
    :user_card,
    :npn_critique_recognition,
    include_condition: -> do
      SiteSetting.npn_critique_engagement_enabled && SiteSetting.npn_critique_chips_enabled &&
        DiscourseNpnCritiqueEngagement::Recognition.level_for(object.id).present?
    end,
  ) { DiscourseNpnCritiqueEngagement::Recognition.level_for(object.id) }

  # The recognition cache derives from these settings, so changing them must
  # invalidate it (score runs handle the rest).
  on(:site_setting_changed) do |name, _old_value, _new_value|
    if %i[
         npn_critique_chip_min_tier
         npn_critique_pillar_badge_name
         npn_critique_engagement_enabled
       ].include?(name)
      DiscourseNpnCritiqueEngagement::Recognition.rebuild!
    end
  end

  # Composer nudge data: only present when the member is past grace and below
  # the healthy give-and-take ratio in the rolling window. The client decides
  # when (and how often) to show the banner.
  add_to_serializer(
    :current_user,
    :npn_critique_nudge,
    include_condition: -> do
      SiteSetting.npn_critique_engagement_enabled && SiteSetting.npn_critique_nudge_enabled
    end,
  ) do
    row = DiscourseNpnCritiqueEngagement::Score.current_for(object)
    { created_topics: row.created_topics, topics_replied: row.topics_replied } if row&.nudge_worthy?
  end

  Discourse::Application.routes.append { mount ::DiscourseNpnCritiqueEngagement::Engine, at: "/" }
end
