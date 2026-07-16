# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  class LeaderboardsController < ::ApplicationController
    requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME

    # GET /critique-engagement/leaderboard
    # The current month's top critics, ranked by weighted critique count.
    # Resets on the 1st so the podium stays reachable.
    def show
      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json do
          period_start = Score.current_period_start
          entries =
            Score
              .for_period(period_start)
              .where("weighted_replies > 0")
              .order(weighted_replies: :desc, score: :desc)
              .limit(SiteSetting.npn_critique_leaderboard_size)
              .includes(:user)
              .reject { |row| row.user.nil? }

          render json: {
                   period_start: period_start,
                   entries: serialize_data(entries, LeaderboardEntrySerializer),
                 }
        end
      end
    end

    # GET /critique-engagement/hall-of-fame
    # Every Pillar of the Community, plus each finalized season's winner.
    def hall_of_fame
      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json { render json: { pillars: pillars, seasons: season_winners } }
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

    def season_winners
      winner_ids = DB.query_single(<<~SQL)
        SELECT DISTINCT ON (period_start) id
        FROM npn_critique_scores
        WHERE finalized AND weighted_replies > 0
        ORDER BY period_start DESC, weighted_replies DESC, score DESC
      SQL

      Score
        .where(id: winner_ids)
        .includes(:user)
        .order(period_start: :desc)
        .reject { |row| row.user.nil? }
        .map do |row|
          {
            period_start: row.period_start,
            username: row.user.username,
            name: row.user.name,
            avatar_template: row.user.avatar_template,
            tier: row.public_tier,
            weighted_replies: row.weighted_replies.round(1),
          }
        end
    end
  end
end
