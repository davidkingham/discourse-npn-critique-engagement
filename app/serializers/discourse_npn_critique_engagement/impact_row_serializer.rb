# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # One month of a member's own standing. The raw score stays out even here —
  # members see tiers and counts, nothing precise enough to grind against.
  class ImpactRowSerializer < ApplicationSerializer
    attributes :period_start, :tier, :weighted_replies, :created_topics, :topics_replied, :ratio

    def weighted_replies
      object.weighted_replies.round(1)
    end

    def ratio
      object.ratio.round(2)
    end
  end
end
