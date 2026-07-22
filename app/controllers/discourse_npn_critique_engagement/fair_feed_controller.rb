# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The composed homepage's data. One request returns every lane, each one
  # serialized as an ordinary topic list so the standard topic-list
  # components render it and `thumbnails` (with real pixel dimensions) comes
  # along for free.
  class FairFeedController < ::ApplicationController
    requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME

    def index
      raise Discourse::NotFound if !Feed.enabled?
      raise Discourse::NotFound if current_user.nil? && !SiteSetting.npn_fair_feed_anonymous

      lanes =
        Feed
          .lanes(current_user)
          .map do |lane|
            # Serialized with its root so each lane carries its own `users` /
            # `primary_groups` sideloads, which is where the client-side
            # TopicList.topicsFrom expects to find them.
            payload =
              serialize_data(lane[:list], TopicListSerializer).merge(
                name: lane[:name],
                layout: lane[:layout],
              )
            attach_pick_genres(payload, lane[:genres]) if lane[:genres].present?
            payload
          end

      render_json_dump(lanes: lanes)
    end

    private

    # The declared genre is per-pick, not a topic attribute, so it rides
    # alongside the serialized topics rather than through the topic serializer
    # (which would compute it for every topic in every lane). The client
    # labels each pick card with it.
    def attach_pick_genres(payload, genres)
      payload[:topic_list][:topics].each do |topic|
        genre = genres[topic[:id]]
        topic[:npn_pick_genre] = genre if genre.present?
      end
    end
  end
end
