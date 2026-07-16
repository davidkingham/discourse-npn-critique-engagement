# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # "Your critique impact" — a member's own standing, never anyone else's.
  # Negative signals stay between the member and this endpoint.
  class ImpactController < ::ApplicationController
    requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME
    requires_login

    HISTORY_MONTHS = 12

    # GET /critique-engagement/impact
    def show
      current = Score.current_for(current_user)
      history =
        MonthlySnapshot
          .where(user_id: current_user.id)
          .order(snapshot_month: :desc)
          .limit(HISTORY_MONTHS)

      render json: {
               window_days: SiteSetting.npn_critique_window_days,
               current: current && ImpactRowSerializer.new(current, root: false).as_json,
               history: serialize_data(history, SnapshotRowSerializer),
               next_action: next_action(current),
               badge_progress: badge_progress(current),
             }
    end

    private

    # Always framed as progress toward the next tier, never as a deficiency.
    def next_action(row)
      return { type: "start" } if row.nil? || (row.weighted_replies == 0 && row.created_topics == 0)
      return { type: "at_top" } if row.excellent?

      target_tier = row.score >= SiteSetting.npn_critique_healthy_score ? "excellent" : "healthy"
      target_score =
        if target_tier == "excellent"
          SiteSetting.npn_critique_excellent_score
        else
          SiteSetting.npn_critique_healthy_score
        end

      count =
        Formula.critiques_to_reach(
          target_score,
          weighted_replies: row.weighted_replies,
          created_topics: row.created_topics,
          topics_replied: row.topics_replied,
          grace: row.new_member?,
        )
      return { type: "keep_going", target_tier: target_tier } if count.nil?

      { type: "critiques_needed", count: count, target_tier: target_tier }
    end

    def badge_progress(row)
      window_start =
        Date.current.beginning_of_month - SiteSetting.npn_critique_pillar_window_months.months

      excellent_months =
        MonthlySnapshot
          .where(user_id: current_user.id, tier: :excellent)
          .where("snapshot_month >= ?", window_start)
          .count

      {
        contributor_on_track: row.present? && (row.healthy? || row.excellent?),
        supporter_on_track: row.present? && row.excellent?,
        pillar: {
          excellent_months: excellent_months,
          required_months: SiteSetting.npn_critique_pillar_required_months,
          window_months: SiteSetting.npn_critique_pillar_window_months,
        },
      }
    end
  end
end
