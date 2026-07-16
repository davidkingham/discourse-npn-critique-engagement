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
  require_relative "lib/discourse_npn_critique_engagement/formula"
  require_relative "lib/discourse_npn_critique_engagement/scorer"
  require_relative "lib/discourse_npn_critique_engagement/badges"
  require_relative "lib/discourse_npn_critique_engagement/season_closer"
  require_relative "app/models/discourse_npn_critique_engagement/score"
  require_relative "app/models/discourse_npn_critique_engagement/outreach_log"
  require_relative "app/serializers/discourse_npn_critique_engagement/leaderboard_entry_serializer"
  require_relative "app/serializers/discourse_npn_critique_engagement/impact_row_serializer"
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

  # Composer nudge data: only present when the member is past grace and below
  # the healthy give-and-take ratio this month. The client decides when (and
  # how often) to show the banner.
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
