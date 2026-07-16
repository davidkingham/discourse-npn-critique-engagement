# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The most-awarded critiques — showcased monthly in the highlights topic
  # and all-time on the hall of fame. Ranked by award reactions received
  # (self-awards excluded), ties broken by likes. Read-restricted categories
  # never surface here: these lists are public.
  module AwardedCritiques
    extend self

    def available?
      SiteSetting.npn_critique_category.present? &&
        SiteSetting.npn_critique_award_reactions.present? &&
        ActiveRecord::Base.connection.table_exists?("discourse_reactions_reactions")
    end

    # Returns [{ post:, award_count: }, ...] best first, optionally limited
    # to critiques written inside a period.
    def top(limit:, period_start: nil, period_end: nil)
      return [] if !available?

      sql = +<<~SQL
        SELECT p.id, COUNT(ru.id) AS award_count
        FROM posts p
        JOIN topics t ON t.id = p.topic_id
        JOIN discourse_reactions_reactions rr
          ON rr.post_id = p.id AND rr.reaction_value IN (:award_reactions)
        JOIN discourse_reactions_reaction_users ru
          ON ru.reaction_id = rr.id AND ru.user_id <> p.user_id
        WHERE t.category_id IN (
            SELECT id FROM categories
            WHERE (id = :category_id OR parent_category_id = :category_id)
              AND NOT read_restricted
          )
          AND t.archetype = 'regular'
          AND t.deleted_at IS NULL
          AND t.visible
          AND p.deleted_at IS NULL
          AND p.post_type = 1
          AND p.post_number > 1
          AND p.user_id > 0
          AND p.user_id <> t.user_id
      SQL
      sql << "  AND p.created_at >= :period_start AND p.created_at < :period_end\n" if period_start
      sql << <<~SQL
        GROUP BY p.id
        ORDER BY award_count DESC, p.like_count DESC, p.id
        LIMIT :limit
      SQL

      params = {
        award_reactions: SiteSetting.npn_critique_award_reactions.to_s.split("|"),
        category_id: SiteSetting.npn_critique_category.to_i,
        limit: limit,
      }
      if period_start
        params[:period_start] = period_start
        params[:period_end] = period_end
      end

      rows = DB.query(sql, params)
      posts = Post.where(id: rows.map(&:id)).includes(:user, :topic).index_by(&:id)

      rows.filter_map do |row|
        post = posts[row.id]
        next if post.nil? || post.user.nil? || post.topic.nil?
        { post: post, award_count: row.award_count }
      end
    end
  end
end
