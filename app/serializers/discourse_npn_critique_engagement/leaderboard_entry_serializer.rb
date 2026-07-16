# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Public recognition is deliberately coarse: rank, tier medal, and weighted
  # critique count — never the raw score, never a below-healthy tier.
  class LeaderboardEntrySerializer < ApplicationSerializer
    attributes :username, :name, :avatar_template, :tier, :weighted_replies

    def username
      object.user.username
    end

    def name
      object.user.name
    end

    def avatar_template
      object.user.avatar_template
    end

    def tier
      object.public_tier
    end

    def weighted_replies
      object.weighted_replies.round(1)
    end
  end
end
