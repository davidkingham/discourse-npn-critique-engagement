# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Shared tier vocabulary for the rolling score and its monthly snapshots.
  # Ordered worst-to-best so tier comparisons read naturally; new_member sits
  # first because it is "no judgement yet", not a rank.
  module HasTier
    extend ActiveSupport::Concern

    TIERS = {
      new_member: 0,
      low_activity: 1,
      priority_outreach: 2,
      watch: 3,
      healthy: 4,
      excellent: 5,
    }.freeze

    # Tiers that may appear on public surfaces (leaderboard medals, chips).
    # Negative signals never leave staff view, so anything below healthy
    # renders as no medal at all.
    PUBLIC_TIERS = %w[healthy excellent].freeze

    included { enum :tier, TIERS }

    def public_tier
      tier if PUBLIC_TIERS.include?(tier)
    end
  end
end
