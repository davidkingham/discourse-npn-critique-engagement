# frozen_string_literal: true

module Jobs
  # Nightly refresh of the current month's critique engagement scores. Also
  # closes any season whose month has ended: the close is keyed off
  # unfinalized past rows, so a missed run is simply caught up the next night.
  class NpnCritiqueScoresRefresh < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      return if !SiteSetting.npn_critique_engagement_enabled
      return if SiteSetting.npn_critique_category.blank?

      DiscourseNpnCritiqueEngagement::SeasonCloser.close_due
      DiscourseNpnCritiqueEngagement::Scorer.run
    end
  end
end
