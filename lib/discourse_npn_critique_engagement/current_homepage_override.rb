# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Core resolves the homepage as
  #   current_user.user_option.homepage || HomepageHelper.resolve(...)
  # so a member who has ever set a "Default Home Page" preference never reaches
  # the custom-homepage gate — their preference wins, even over a theme's
  # custom homepage. That is core behaviour and normally desirable, but it
  # means rolling the fair feed out to an audience misses everyone who once
  # picked a homepage.
  #
  # Prepended ahead of both definitions of #current_homepage (the controller's,
  # which drives crawler/SEO checks, and the helper's, which drives the
  # `discourse_current_homepage` meta tag the client routes on), this returns
  # "custom" whenever the feed is meant to show for the viewer — overriding
  # their preference. Everyone outside the audience, and everyone when the
  # override setting is off, falls through to core's resolution untouched.
  module CurrentHomepageOverride
    def current_homepage
      if SiteSetting.npn_fair_feed_override_homepage_preference &&
           DiscourseNpnCritiqueEngagement::Feed.visible_to?(current_user)
        "custom"
      else
        super
      end
    end
  end
end
