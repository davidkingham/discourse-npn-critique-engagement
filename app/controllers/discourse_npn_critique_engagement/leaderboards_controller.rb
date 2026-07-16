# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  class LeaderboardsController < ::ApplicationController
    requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME

    # GET /critique-engagement/leaderboard
    # The most generous critics of the trailing window, ranked by weighted
    # critique count. Continuously rolling — standing ages out naturally, so
    # the podium stays reachable without ever resetting.
    def show
      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json do
          entries =
            Score
              .where("weighted_replies > 0")
              .order(weighted_replies: :desc, score: :desc)
              .limit(SiteSetting.npn_critique_leaderboard_size)
              .includes(:user)
              .reject { |row| row.user.nil? }

          render json: {
                   window_days: SiteSetting.npn_critique_window_days,
                   entries: serialize_data(entries, LeaderboardEntrySerializer),
                 }
        end
      end
    end

    # GET /critique-engagement/hall-of-fame
    # Every Critique Steward, plus each month's top critic from the snapshots.
    def hall_of_fame
      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json { render json: { pillars: pillars, seasons: monthly_winners } }
      end
    end

    private

    def pillars
      badge = Badge.find_by(name: SiteSetting.npn_critique_pillar_badge_name)
      return [] if badge.nil?

      UserBadge
        .where(badge_id: badge.id)
        .includes(:user)
        .order(:granted_at)
        .reject { |user_badge| user_badge.user.nil? }
        .map do |user_badge|
          {
            username: user_badge.user.username,
            name: user_badge.user.name,
            avatar_template: user_badge.user.avatar_template,
            granted_at: user_badge.granted_at,
          }
        end
    end

    def monthly_winners
      winner_ids = DB.query_single(<<~SQL)
        SELECT DISTINCT ON (snapshot_month) id
        FROM npn_critique_monthly_snapshots
        WHERE weighted_replies > 0
        ORDER BY snapshot_month DESC, weighted_replies DESC, score DESC
      SQL

      MonthlySnapshot
        .where(id: winner_ids)
        .includes(:user)
        .order(snapshot_month: :desc)
        .reject { |snapshot| snapshot.user.nil? }
        .map do |snapshot|
          {
            month: snapshot.snapshot_month,
            username: snapshot.user.username,
            name: snapshot.user.name,
            avatar_template: snapshot.user.avatar_template,
            tier: snapshot.public_tier,
            weighted_replies: snapshot.weighted_replies.round(1),
          }
        end
    end
  end
end
