# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  module Admin
    class ReportsController < ::Admin::StaffController
      requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME

      HEALTH_MONTHS = 12

      # GET /admin/plugins/critique-engagement/report?period=YYYY-MM
      # Every member scored for the month. Sorting and tier filtering happen
      # client-side — the community is small enough to ship the whole month.
      def index
        period_start = requested_period || Score.current_period_start

        rows =
          Score
            .for_period(period_start)
            .includes(:user)
            .order(score: :desc)
            .reject { |row| row.user.nil? }

        user_ids = rows.map(&:user_id)
        previous_scores =
          Score
            .for_period(period_start.prev_month)
            .where(user_id: user_ids)
            .pluck(:user_id, :score)
            .to_h

        render json: {
                 period_start: period_start,
                 periods: available_periods,
                 rows:
                   serialize_data(
                     rows,
                     ReportRowSerializer,
                     previous_scores: previous_scores,
                     outreach_logs: OutreachLog.latest_for(user_ids),
                   ),
               }
      end

      # GET /admin/plugins/critique-engagement/health
      # Category health over the trailing year: tier distribution, critique
      # volume, and median give-and-take ratio per month.
      def health
        aggregates =
          Score
            .group(:period_start)
            .order(period_start: :desc)
            .limit(HEALTH_MONTHS)
            .pluck(
              :period_start,
              Arel.sql("COUNT(*)"),
              Arel.sql("SUM(weighted_replies)"),
              Arel.sql("PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ratio)"),
            )

        tier_counts =
          Score.where(period_start: aggregates.map(&:first)).group(:period_start, :tier).count

        render json: {
                 months:
                   aggregates.map do |period_start, members, total_weighted, median_ratio|
                     {
                       period_start: period_start,
                       members: members,
                       total_weighted_replies: total_weighted.to_f.round(1),
                       median_ratio: median_ratio.to_f.round(2),
                       tiers:
                         Score.tiers.keys.index_with do |tier|
                           tier_counts[[period_start, tier]] || 0
                         end,
                     }
                   end,
               }
      end

      private

      def requested_period
        return if params[:period].blank?

        period = Date.strptime(params[:period], "%Y-%m")
        period.beginning_of_month
      rescue Date::Error
        raise Discourse::InvalidParameters.new(:period)
      end

      def available_periods
        Score.distinct.order(period_start: :desc).pluck(:period_start)
      end
    end
  end
end
