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
register_svg_icon "star"
register_svg_icon "image"
register_svg_icon "arrow-rotate-left"
register_svg_icon "xmark"
register_svg_icon "chevron-left"
register_svg_icon "chevron-right"

module ::DiscourseNpnCritiqueEngagement
  PLUGIN_NAME = "discourse-npn-critique-engagement"

  # Widths the feed's three layouts ask for, at 1x and 2x. Registered with
  # core so thumbnail generation doesn't depend on a theme component, and so
  # every list item carries real dimensions for the box we reserve.
  THUMBNAIL_SIZES = [[400, 400], [800, 800], [1200, 1200], [2400, 2400]].freeze
end

require_relative "lib/discourse_npn_critique_engagement/engine"

after_initialize do
  require_relative "lib/discourse_npn_critique_engagement/has_tier"
  require_relative "lib/discourse_npn_critique_engagement/formula"
  require_relative "lib/discourse_npn_critique_engagement/scorer"
  require_relative "lib/discourse_npn_critique_engagement/fair_ranking"
  require_relative "lib/discourse_npn_critique_engagement/topic_query_extension"
  require_relative "lib/discourse_npn_critique_engagement/feed"
  require_relative "lib/discourse_npn_critique_engagement/current_homepage_override"
  require_relative "lib/discourse_npn_critique_engagement/discussion_prompt"
  require_relative "lib/discourse_npn_critique_engagement/reach_metrics"
  require_relative "lib/discourse_npn_critique_engagement/badges"
  require_relative "lib/discourse_npn_critique_engagement/recognition"
  require_relative "lib/discourse_npn_critique_engagement/awarded_critiques"
  require_relative "lib/discourse_npn_critique_engagement/genre_tags"
  require_relative "lib/discourse_npn_critique_engagement/editors_pick"
  require_relative "lib/discourse_npn_critique_engagement/monthly_recognition"
  require_relative "app/models/discourse_npn_critique_engagement/score"
  require_relative "app/models/discourse_npn_critique_engagement/monthly_snapshot"
  require_relative "app/models/discourse_npn_critique_engagement/outreach_log"
  require_relative "app/models/discourse_npn_critique_engagement/outreach_claim"
  require_relative "app/models/discourse_npn_critique_engagement/pending_pick"
  require_relative "app/serializers/discourse_npn_critique_engagement/leaderboard_entry_serializer"
  require_relative "app/serializers/discourse_npn_critique_engagement/impact_row_serializer"
  require_relative "app/serializers/discourse_npn_critique_engagement/snapshot_row_serializer"
  require_relative "app/serializers/discourse_npn_critique_engagement/outreach_log_serializer"
  require_relative "app/serializers/discourse_npn_critique_engagement/report_row_serializer"
  require_relative "app/controllers/discourse_npn_critique_engagement/leaderboards_controller"
  require_relative "app/controllers/discourse_npn_critique_engagement/impact_controller"
  require_relative "app/controllers/discourse_npn_critique_engagement/editors_picks_controller"
  require_relative "app/controllers/discourse_npn_critique_engagement/moderate_controller"
  require_relative "app/controllers/discourse_npn_critique_engagement/fair_feed_controller"
  require_relative "app/controllers/discourse_npn_critique_engagement/admin/reports_controller"
  require_relative "app/controllers/discourse_npn_critique_engagement/admin/outreach_controller"
  require_relative "app/jobs/regular/npn_finalize_editors_pick"
  require_relative "app/jobs/scheduled/npn_critique_scores_refresh"
  require_relative "app/jobs/scheduled/npn_discussion_prompt"

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

  # Sending the member a PM completes an outreach claim on its own — the
  # moderator shouldn't also have to log the contact by hand.
  on(:topic_created) do |topic, _opts, user|
    DiscourseNpnCritiqueEngagement::OutreachClaim.complete_from_pm(topic, user)
  end

  # The recognition cache derives from these settings, so changing them must
  # invalidate it (score runs handle the rest).
  on(:site_setting_changed) do |name, _old_value, _new_value|
    if %i[
         npn_critique_chip_min_tier
         npn_critique_pillar_badge_name
         npn_critique_engagement_enabled
         npn_critique_rising_enabled
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

  # Core only serializes `excerpt` on a topic list for pinned topics, or when
  # a site-wide setting or theme modifier turns it on. The conversation lane
  # is text rows — an excerpt is most of what makes one worth reading — so
  # the feed carries its own. `topics.excerpt` is a stored column, so this
  # costs nothing beyond the bytes.
  add_to_serializer(
    :topic_list_item,
    :npn_excerpt,
    include_condition: -> do
      SiteSetting.npn_critique_engagement_enabled && SiteSetting.npn_fair_feed_enabled &&
        object.excerpt.present?
    end,
  ) { object.excerpt }

  # `order:fair` — the equity ordering, as a first-class sort. Registering it
  # here rather than building a bespoke list means /filter?q=... order:fair is
  # linkable and paginated, and the same expression can back the category
  # sort dropdown and the homepage feed. An unrecognized order: key falls
  # through to the custom filter registry in TopicsFilter#order_by.
  add_filter_custom_filter("order:fair") do |scope, direction, _guardian|
    DiscourseNpnCritiqueEngagement::FairRanking.order_fair(scope, direction)
  end

  # The same ordering for TopicQuery-backed lists, so a category whose
  # sort_order is "fair" (and /latest?order=fair) honours it too.
  register_modifier(
    :topic_query_apply_ordering_result,
  ) do |result, order_option, sort_dir, _opts, _tq|
    if order_option.to_s == "fair"
      DiscourseNpnCritiqueEngagement::FairRanking.order_fair(result, sort_dir)
    end
  end

  # Autocomplete tip on the /filter input.
  register_modifier(:topics_filter_options) do |options, _guardian|
    options << {
      name: "order:fair",
      description: I18n.t("npn_critique_engagement.filter_tips.order_fair"),
    }
    options
  end

  reloadable_patch do
    TopicQuery.prepend(DiscourseNpnCritiqueEngagement::TopicQueryExtension)
    # Both the controller (crawler/SEO checks) and the helper (the homepage
    # meta tag the client routes on) define #current_homepage; override both so
    # the feed can outrank a member's homepage preference.
    ApplicationController.prepend(DiscourseNpnCritiqueEngagement::CurrentHomepageOverride)
    ApplicationHelper.prepend(DiscourseNpnCritiqueEngagement::CurrentHomepageOverride)
  end

  # Take over "/" for the composed homepage. Logged-in members only unless
  # the setting says otherwise: anonymous visitors keep Latest, which is the
  # crawlable surface. A member who sets their own homepage preference
  # overrides this anyway — core handles that.
  # apply_modifier forwards its extra arguments positionally, so HomepageHelper's
  # `request:`/`current_user:` arrive as a single hash rather than as keywords.
  register_modifier(:custom_homepage_enabled) do |enabled, args|
    enabled || DiscourseNpnCritiqueEngagement::Feed.visible_to?(args[:current_user])
  end

  # Thumbnails for the feed's layouts. Registering the sizes here rather than
  # relying on a theme component is what lets every lane reserve the right
  # box before an image loads: core serializes real width/height per size on
  # every topic list item.
  DiscourseNpnCritiqueEngagement::THUMBNAIL_SIZES.each do |size|
    register_topic_thumbnail_size(size)
  end

  Discourse::Application.routes.append { mount ::DiscourseNpnCritiqueEngagement::Engine, at: "/" }
end
