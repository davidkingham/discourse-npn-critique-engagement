# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Computes trailing-window engagement aggregates for every member who was
  # active in the critique category, scores them through Formula, and upserts
  # one rolling row per member. Runs nightly; contributions age out of the
  # window naturally, so nothing ever resets.
  class Scorer
    FIRST_RUN_KEY = "first_run_at"

    # Strips [quote]...[/quote] blocks before measuring length, so quoting a
    # wall of text earns nothing. The prototype's pattern, single-quoted so
    # the backslashes reach Postgres intact; passed as a bind param rather
    # than interpolated.
    QUOTE_PATTERN = '\[quote.*?\[/quote\]'

    def self.run
      new.run
    end

    # When the plugin first produced data — MonthlyRecognition uses this to
    # avoid recording snapshots for months the plugin wasn't watching.
    def self.first_run_at
      value = PluginStore.get(PLUGIN_NAME, FIRST_RUN_KEY)
      value && Time.zone.parse(value)
    end

    def run
      return if category_id.blank?

      if self.class.first_run_at.nil?
        PluginStore.set(PLUGIN_NAME, FIRST_RUN_KEY, Time.zone.now.iso8601)
      end

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
          tier = Formula.tier_for(user: user, score: score, created_topics: row.created_topics)

          record = Score.find_or_initialize_by(user_id: row.user_id)
          record.update!(
            score: score,
            tier: tier,
            created_topics: row.created_topics,
            topics_replied: row.topics_replied,
            weighted_replies: row.weighted_replies.round(2),
            awards_received: row.awards_received,
            ratio:
              Formula.ratio(
                created_topics: row.created_topics,
                topics_replied: row.topics_replied,
              ).round(3),
            computed_at: computed_at,
          )
        end

        # Members whose window emptied (activity aged out or was deleted)
        # drop off entirely.
        Score.where.not(user_id: rows.map(&:user_id)).delete_all
      end

      Recognition.rebuild!
    end

    private

    # Per-member trailing-window aggregates, ported from the Data Explorer
    # prototype: replies weighted by substance (length tiers after
    # quote-stripping, a capped like bonus, a capped award-reaction bonus, and
    # discounted follow-up replies) against topics posted. The critique
    # category is scoped with its subcategories. Deleted posts, whispers, and
    # self-replies never count.
    #
    # The award fragments are assembled conditionally so the query works when
    # discourse-reactions is absent. Every fragment is a trusted constant —
    # all runtime values still travel as bind params.
    def aggregates_sql
      <<~SQL
        WITH critique_categories AS (
          SELECT id FROM categories
          WHERE id = :category_id OR parent_category_id = :category_id
        ),
        period_posts AS (
          SELECT
            p.id,
            p.user_id,
            p.topic_id,
            t.user_id AS topic_user_id,
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
            AND p.created_at >= :window_start
            AND p.created_at < :window_end
        )#{awards_cte},
        substantive AS (
          SELECT
            period_posts.user_id,
            period_posts.topic_id,
            CASE
              WHEN period_posts.effective_length >= :long_length THEN :long_multiplier
              WHEN period_posts.effective_length >= :medium_length THEN :medium_multiplier
              ELSE 1.0
            END
            + LEAST(period_posts.like_count * :like_bonus, :like_bonus_cap)
            #{awards_value_fragment} AS reply_value,
            #{awards_count_fragment} AS award_count,
            ROW_NUMBER() OVER (
              PARTITION BY period_posts.user_id, period_posts.topic_id
              ORDER BY period_posts.post_number
            ) AS reply_rank
          FROM period_posts
          #{awards_join_fragment}
          WHERE period_posts.effective_length >= :min_length
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
            COUNT(DISTINCT topic_id) AS topics_replied,
            SUM(award_count) AS awards_received
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
            AND t.created_at >= :window_start
            AND t.created_at < :window_end
          GROUP BY t.user_id
        )
        SELECT
          COALESCE(replies.user_id, creations.user_id) AS user_id,
          COALESCE(replies.weighted_replies, 0) AS weighted_replies,
          COALESCE(replies.topics_replied, 0) AS topics_replied,
          COALESCE(replies.awards_received, 0) AS awards_received,
          COALESCE(creations.created_topics, 0) AS created_topics
        FROM replies
        FULL OUTER JOIN creations ON creations.user_id = replies.user_id
      SQL
    end

    # Award reactions on a critique, capped per reply. An award from the
    # topic owner — the person the critique was written for — carries extra
    # weight: "this helped my work" is the strongest signal there is.
    def awards_cte
      return "" if !awards_enabled?

      ",\n" + <<~SQL.chomp
        post_awards AS (
          SELECT
            period_posts.id AS post_id,
            LEAST(
              SUM(
                CASE
                  WHEN ru.user_id = period_posts.topic_user_id
                  THEN :award_bonus * :owner_award_multiplier
                  ELSE :award_bonus
                END
              ),
              :award_bonus_cap
            ) AS award_bonus,
            COUNT(*) AS award_count
          FROM period_posts
          JOIN discourse_reactions_reactions rr
            ON rr.post_id = period_posts.id AND rr.reaction_value IN (:award_reactions)
          JOIN discourse_reactions_reaction_users ru
            ON ru.reaction_id = rr.id AND ru.user_id <> period_posts.user_id
          GROUP BY period_posts.id
        )
      SQL
    end

    def awards_value_fragment
      awards_enabled? ? "+ COALESCE(post_awards.award_bonus, 0)" : ""
    end

    def awards_count_fragment
      awards_enabled? ? "COALESCE(post_awards.award_count, 0)" : "0"
    end

    def awards_join_fragment
      awards_enabled? ? "LEFT JOIN post_awards ON post_awards.post_id = period_posts.id" : ""
    end

    def awards_enabled?
      return @awards_enabled if defined?(@awards_enabled)
      @awards_enabled =
        award_reactions.present? &&
          ActiveRecord::Base.connection.table_exists?("discourse_reactions_reactions")
    end

    def award_reactions
      SiteSetting.npn_critique_award_reactions.to_s.split("|")
    end

    def aggregates
      params = {
        quote_pattern: QUOTE_PATTERN,
        category_id: category_id,
        window_start: SiteSetting.npn_critique_window_days.days.ago,
        window_end: Time.zone.now,
        min_length: SiteSetting.npn_critique_min_reply_length,
        medium_length: SiteSetting.npn_critique_medium_reply_length,
        long_length: SiteSetting.npn_critique_long_reply_length,
        medium_multiplier: SiteSetting.npn_critique_medium_reply_multiplier,
        long_multiplier: SiteSetting.npn_critique_long_reply_multiplier,
        like_bonus: SiteSetting.npn_critique_like_bonus,
        like_bonus_cap: SiteSetting.npn_critique_like_bonus_cap,
        followup_multiplier: SiteSetting.npn_critique_followup_multiplier,
        followup_cap: SiteSetting.npn_critique_followup_cap,
      }
      if awards_enabled?
        params[:award_reactions] = award_reactions
        params[:award_bonus] = SiteSetting.npn_critique_award_bonus
        params[:award_bonus_cap] = SiteSetting.npn_critique_award_bonus_cap
        params[:owner_award_multiplier] = SiteSetting.npn_critique_owner_award_multiplier
      end

      DB.query(aggregates_sql, params)
    end

    def category_id
      SiteSetting.npn_critique_category.presence&.to_i
    end
  end
end
