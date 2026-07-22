# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  module Admin
    class ReportsController < ::Admin::StaffController
      requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME

      HEALTH_MONTHS = 12
      REACH_WEEKS = 12

      # GET /admin/plugins/critique-engagement/report?period=YYYY-MM
      # No period: the live rolling standing (trend vs. the latest snapshot).
      # With a period: that month's snapshot (trend vs. the month before).
      # Sorting and tier filtering happen client-side — the community is
      # small enough to ship the whole set.
      def index
        month = requested_month

        if month
          rows = MonthlySnapshot.for_month(month).includes(:user).order(score: :desc)
          previous_scores = snapshot_scores(month.prev_month, rows.map(&:user_id))
        else
          rows = Score.includes(:user).order(score: :desc)
          previous_scores = snapshot_scores(MonthlySnapshot.latest_month, rows.map(&:user_id))
        end
        rows = rows.reject { |row| row.user.nil? }

        render json: {
                 window_days: SiteSetting.npn_critique_window_days,
                 period: month,
                 periods: available_months,
                 rows:
                   serialize_data(
                     rows,
                     ReportRowSerializer,
                     previous_scores: previous_scores,
                     outreach_logs: OutreachLog.latest_for(rows.map(&:user_id)),
                   ),
               }
      end

      # GET /admin/plugins/critique-engagement/health
      # Category health over time: tier distribution, critique volume, and
      # median give-and-take ratio — the live window first, then the monthly
      # snapshots.
      def health
        render json: {
                 months: [current_health] + snapshot_health,
                 reach: ReachMetrics.weekly(weeks: REACH_WEEKS),
               }
      end

      private

      def requested_month
        return if params[:period].blank?

        month = Date.strptime(params[:period], "%Y-%m").beginning_of_month
        raise Discourse::NotFound if !MonthlySnapshot.for_month(month).exists?
        month
      rescue Date::Error
        raise Discourse::InvalidParameters.new(:period)
      end

      def snapshot_scores(month, user_ids)
        return {} if month.nil?
        MonthlySnapshot.for_month(month).where(user_id: user_ids).pluck(:user_id, :score).to_h
      end

      def available_months
        MonthlySnapshot.distinct.order(snapshot_month: :desc).pluck(:snapshot_month)
      end

      def current_health
        {
          current: true,
          members: Score.count,
          total_weighted_replies: Score.sum(:weighted_replies).to_f.round(1),
          median_ratio: median_ratio_of(Score),
          tiers: tier_counts_of(Score.group(:tier).count),
        }
      end

      def snapshot_health
        aggregates =
          MonthlySnapshot
            .group(:snapshot_month)
            .order(snapshot_month: :desc)
            .limit(HEALTH_MONTHS)
            .pluck(
              :snapshot_month,
              Arel.sql("COUNT(*)"),
              Arel.sql("SUM(weighted_replies)"),
              Arel.sql("PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ratio)"),
            )

        tier_counts =
          MonthlySnapshot
            .where(snapshot_month: aggregates.map(&:first))
            .group(:snapshot_month, :tier)
            .count

        aggregates.map do |month, members, total_weighted, median_ratio|
          {
            month: month,
            members: members,
            total_weighted_replies: total_weighted.to_f.round(1),
            median_ratio: median_ratio.to_f.round(2),
            tiers: HasTier::TIERS.keys.index_with { |tier| tier_counts[[month, tier.to_s]] || 0 },
          }
        end
      end

      def median_ratio_of(scope)
        scope.pick(Arel.sql("PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ratio)")).to_f.round(2)
      end

      def tier_counts_of(counts)
        HasTier::TIERS.keys.index_with { |tier| counts[tier.to_s] || 0 }
      end
    end
  end
end
