# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Public recognition is deliberately coarse: rank and tier medal only —
  # never the raw score, never the weighted count, never a below-healthy
  # tier. The ordering still comes from the weighted count server-side; the
  # number itself stays on the admin report.
  class LeaderboardEntrySerializer < ApplicationSerializer
    attributes :username, :name, :avatar_template, :tier

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
  end
end
