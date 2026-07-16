# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Computes one month of critique engagement aggregates for every member who
  # was active in the critique category, scores them through Formula, and
  # upserts the results into npn_critique_scores. Finalized (season-closed)
  # rows are never touched.
  class Scorer
    # Strips [quote]...[/quote] blocks before measuring length, so quoting a
    # wall of text earns nothing. The prototype's pattern, single-quoted so
    # the backslashes reach Postgres intact; passed as a bind param rather
    # than interpolated.
    QUOTE_PATTERN = '\[quote.*?\[/quote\]'

    # Per-member monthly aggregates, ported from the Data Explorer prototype:
    # replies weighted by substance (length tiers after quote-stripping, a
    # capped like bonus, discounted follow-up replies) against topics posted.
    # The critique category is scoped with its subcategories. Deleted posts,
    # whispers, and self-replies never count.
    AGGREGATES_SQL = <<~SQL
      WITH critique_categories AS (
        SELECT id FROM categories
        WHERE id = :category_id OR parent_category_id = :category_id
      ),
      period_posts AS (
        SELECT
          p.user_id,
          p.topic_id,
          p.post_number,
          p.like_count,
          LENGTH(REGEXP_REPLACE(p.raw, :quote_pattern, '', 'gi')) AS effective_length
        FROM posts p
        JOIN topics t ON t.id = p.topic_id
        WHERE t.category_id IN (SELECT id FROM critique_categories)
          AND t.archetype = 'regular'
          AND t.deleted_at IS NULL
          AND p.deleted_at IS NULL
          AND p.post_type = 1
          AND p.post_number > 1
          AND p.user_id > 0
          AND p.user_id <> t.user_id
          AND p.created_at >= :period_start
          AND p.created_at < :period_end
      ),
      substantive AS (
        SELECT
          user_id,
          topic_id,
          CASE
            WHEN effective_length >= :long_length THEN :long_multiplier
            WHEN effective_length >= :medium_length THEN :medium_multiplier
            ELSE 1.0
          END + LEAST(like_count * :like_bonus, :like_bonus_cap) AS reply_value,
          ROW_NUMBER() OVER (PARTITION BY user_id, topic_id ORDER BY post_number) AS reply_rank
        FROM period_posts
        WHERE effective_length >= :min_length
      ),
      replies AS (
        SELECT
          user_id,
          SUM(
            CASE
              WHEN reply_rank = 1 THEN reply_value
              WHEN reply_rank <= 1 + :followup_cap THEN reply_value * :followup_multiplier
              ELSE 0
            END
          ) AS weighted_replies,
          COUNT(DISTINCT topic_id) AS topics_replied
        FROM substantive
        GROUP BY user_id
      ),
      creations AS (
        SELECT t.user_id, COUNT(*) AS created_topics
        FROM topics t
        WHERE t.category_id IN (SELECT id FROM critique_categories)
          AND t.archetype = 'regular'
          AND t.deleted_at IS NULL
          AND t.user_id > 0
          AND t.created_at >= :period_start
          AND t.created_at < :period_end
        GROUP BY t.user_id
      )
      SELECT
        COALESCE(replies.user_id, creations.user_id) AS user_id,
        COALESCE(replies.weighted_replies, 0) AS weighted_replies,
        COALESCE(replies.topics_replied, 0) AS topics_replied,
        COALESCE(creations.created_topics, 0) AS created_topics
      FROM replies
      FULL OUTER JOIN creations ON creations.user_id = replies.user_id
    SQL

    def self.run(period_start = Score.current_period_start)
      new(period_start).run
    end

    def initialize(period_start)
      @period_start = period_start.to_date.beginning_of_month
    end

    def run
      return if category_id.blank?

      rows = aggregates
      users = User.real.where(id: rows.map(&:user_id)).index_by(&:id)
      computed_at = Time.zone.now

      Score.transaction do
        rows.each do |row|
          user = users[row.user_id]
          next if user.nil?

          grace =
            Formula.grace_protected?(
              user: user,
              period_start: @period_start,
              created_topics: row.created_topics,
              topics_replied: row.topics_replied,
            )
          score =
            Formula.score(
              weighted_replies: row.weighted_replies,
              created_topics: row.created_topics,
              topics_replied: row.topics_replied,
              grace: grace,
            )
          tier =
            Formula.tier_for(
              user: user,
              score: score,
              created_topics: row.created_topics,
              period_start: @period_start,
            )

          record = Score.find_or_initialize_by(user_id: row.user_id, period_start: @period_start)
          next if record.finalized?

          record.update!(
            score: score,
            tier: tier,
            created_topics: row.created_topics,
            topics_replied: row.topics_replied,
            weighted_replies: row.weighted_replies.round(2),
            ratio:
              Formula.ratio(
                created_topics: row.created_topics,
                topics_replied: row.topics_replied,
              ).round(3),
            computed_at: computed_at,
          )
        end

        # A member's activity can disappear mid-month (posts deleted); their
        # stale row must go with it.
        Score
          .for_period(@period_start)
          .where(finalized: false)
          .where.not(user_id: rows.map(&:user_id))
          .delete_all
      end
    end

    private

    def aggregates
      DB.query(
        AGGREGATES_SQL,
        quote_pattern: QUOTE_PATTERN,
        category_id: category_id,
        period_start: @period_start,
        period_end: @period_start.next_month,
        min_length: SiteSetting.npn_critique_min_reply_length,
        medium_length: SiteSetting.npn_critique_medium_reply_length,
        long_length: SiteSetting.npn_critique_long_reply_length,
        medium_multiplier: SiteSetting.npn_critique_medium_reply_multiplier,
        long_multiplier: SiteSetting.npn_critique_long_reply_multiplier,
        like_bonus: SiteSetting.npn_critique_like_bonus,
        like_bonus_cap: SiteSetting.npn_critique_like_bonus_cap,
        followup_multiplier: SiteSetting.npn_critique_followup_multiplier,
        followup_cap: SiteSetting.npn_critique_followup_cap,
      )
    end

    def category_id
      SiteSetting.npn_critique_category.presence&.to_i
    end
  end
end
