# frozen_string_literal: true

module Jobs
  # Nightly refresh of the rolling critique engagement scores. Also records
  # the monthly snapshot once a month has ended: the recording is keyed off
  # the missing snapshot, so a missed run is simply caught up the next night.
  class NpnCritiqueScoresRefresh < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      return if !SiteSetting.npn_critique_engagement_enabled
      return if SiteSetting.npn_critique_category.blank?

      DiscourseNpnCritiqueEngagement::MonthlyRecognition.record_due
      DiscourseNpnCritiqueEngagement::Scorer.run
    end
  end
end
