# frozen_string_literal: true

module Jobs
  # Posts the weekly discussion question. Jobs::Scheduled has no cron
  # expression, so like the weekly-challenge publisher it polls often and the
  # publisher returns early on all but the one run a week that actually posts.
  class NpnDiscussionPrompt < ::Jobs::Scheduled
    every 30.minutes

    def execute(_args)
      DiscourseNpnCritiqueEngagement::DiscussionPrompt.post_due
    end
  end
end
