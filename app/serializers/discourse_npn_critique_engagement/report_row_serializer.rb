# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Staff report row: the full picture, including raw score and trend against
  # the previous month. Staff-only by route constraint.
  class ReportRowSerializer < ApplicationSerializer
    attributes :user_id,
               :username,
               :name,
               :avatar_template,
               :score,
               :tier,
               :created_topics,
               :topics_replied,
               :weighted_replies,
               :ratio,
               :trend,
               :finalized,
               :last_outreach

    def username
      object.user.username
    end

    def name
      object.user.name
    end

    def avatar_template
      object.user.avatar_template
    end

    def score
      object.score.round(1)
    end

    def weighted_replies
      object.weighted_replies.round(1)
    end

    def ratio
      object.ratio.round(2)
    end

    def trend
      previous = @options[:previous_scores]&.dig(object.user_id)
      previous && (object.score - previous).round(1)
    end

    def include_trend?
      @options[:previous_scores]&.key?(object.user_id)
    end

    def last_outreach
      log = @options[:outreach_logs]&.dig(object.user_id)
      log && OutreachLogSerializer.new(log, root: false).as_json
    end

    def include_last_outreach?
      @options[:outreach_logs]&.key?(object.user_id)
    end
  end
end
