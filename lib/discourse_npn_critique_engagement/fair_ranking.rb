# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Who is still waiting for a critique, and in what order.
  #
  # The candidate definition used to live inside ModerateController; it now
  # lives here so the staff triage queue and the member-facing feed can never
  # disagree about what "still waiting" means.
  #
  # Two orderings sit on that one candidate set, because they do different
  # jobs. Moderators work a triage list top-down and want strict priority, so
  # #triage_sort_key keeps the original new-members-then-standing order. The
  # feed is a browse surface and wants attention spread across authors, so
  # #order_fair leads with a per-author round-robin. Both draw on the same
  # rolling scores.
  module FairRanking
    # Everything after this point in the ORDER BY is a tiebreak, so the feed
    # is deterministic between requests even when scores tie exactly.
    TIEBREAK = "topics.created_at ASC, topics.id ASC"

    SCORES_JOIN_ALIAS = "npn_scores"
    AUTHORS_JOIN_ALIAS = "npn_authors"

    # A reply only counts if it is substantive by the scorer's own definition:
    # long enough after quote-stripping, from someone other than the poster.
    # Kept identical to Scorer so a topic can never be "critiqued" for the
    # feed but uncritiqued for scoring.
    NO_SUBSTANTIVE_REPLY_SQL = <<~SQL
      NOT EXISTS (
        SELECT 1
        FROM posts p
        WHERE p.topic_id = topics.id
          AND p.post_number > 1
          AND p.deleted_at IS NULL
          AND p.post_type = 1
          AND p.user_id > 0
          AND p.user_id <> topics.user_id
          AND LENGTH(REGEXP_REPLACE(p.raw, :quote_pattern, '', 'gi')) >= :min_length
      )
    SQL

    # Weekly-challenge ANNOUNCEMENT topics never need critiques. Challenge
    # entries do, which is why this keys on the announcement marker rather
    # than on the challenge tag.
    NOT_CHALLENGE_ANNOUNCEMENT_SQL = <<~SQL
      NOT EXISTS (
        SELECT 1
        FROM topic_custom_fields tcf
        WHERE tcf.topic_id = topics.id AND tcf.name = 'npn_weekly_challenge_slug'
      )
    SQL

    class << self
      # The critique category and its subcategories. Not memoized: the
      # setting can change under a long-lived process, and the pluck is
      # cheap next to the queries it feeds.
      def category_ids
        category_id = SiteSetting.npn_critique_category.presence&.to_i
        return [] if category_id.nil?

        Category.where("id = :id OR parent_category_id = :id", id: category_id).pluck(:id)
      end

      # Topics in the critique tree still waiting for a substantive critique.
      # Takes a scope so callers can compose on TopicQuery's secured
      # default_results rather than on Topic.all.
      def candidates(scope: Topic.all, cutoff: coverage_cutoff)
        ids = category_ids
        return scope.none if ids.blank?

        scope = scope.where(category_id: ids)
        scope = scope.where(archetype: Archetype.default)
        scope = scope.where(deleted_at: nil, visible: true)
        scope = scope.where("topics.user_id > 0")
        scope = scope.where("topics.created_at >= ?", cutoff)
        scope = scope.where(NO_SUBSTANTIVE_REPLY_SQL, substantive_reply_params)
        scope = scope.where(NOT_CHALLENGE_ANNOUNCEMENT_SQL)
        scope = exclude_tags(scope)
        exclude_title_prefixes(scope)
      end

      # The feed ordering. Applies to any scope, not just candidates, so the
      # same expression can back `order:fair` over a whole category.
      #
      # Leads with ROW_NUMBER partitioned by author: everyone's strongest
      # topic first, then everyone's second, and so on. That is a one-per-
      # author cap in the visible fold without any tuning constant, and it is
      # what stops a handful of regulars owning the top of the page.
      def order_fair(scope, direction = "DESC")
        dir = direction.to_s.casecmp("ASC").zero? ? "ASC" : "DESC"
        scope = join_ranking_tables(scope)

        scope.reorder(
          Arel.sql(
            sanitize(
              "ROW_NUMBER() OVER (PARTITION BY topics.user_id ORDER BY #{score_sql} DESC) ASC, " \
                "#{score_sql} #{dir}, #{TIEBREAK}",
              score_params,
            ),
          ),
        )
      end

      # Ordering for lanes outside the critique tree.
      #
      # The rolling score deliberately plays no part here: Scorer only counts
      # replies inside the critique category, so ranking a discussion by it
      # would demote a member who is active in discussions but doesn't
      # critique — punishing exactly the behaviour these lanes exist to
      # encourage. Unanswered first, one per author, newest as the tiebreak.
      def order_conversation(scope)
        scope.reorder(
          Arel.sql(
            "ROW_NUMBER() OVER (PARTITION BY topics.user_id ORDER BY topics.created_at DESC) ASC, " \
              "(CASE WHEN topics.posts_count <= 1 THEN 0 ELSE 1 END) ASC, " \
              "topics.created_at DESC, topics.id DESC",
          ),
        )
      end

      # LEFT JOINs, so a member with no rolling score row (nobody active in
      # the window yet) still appears rather than dropping out of the feed.
      # Aliased away from `users` so we never collide with a join core has
      # already made, and applied at most once — TopicsFilter and TopicQuery
      # can both route through here for the same request.
      def join_ranking_tables(scope)
        return scope if scope.joins_values.any? { |join| join.to_s.include?(SCORES_JOIN_ALIAS) }

        scope.joins(
          "LEFT JOIN npn_critique_rolling_scores #{SCORES_JOIN_ALIAS} " \
            "ON #{SCORES_JOIN_ALIAS}.user_id = topics.user_id",
        ).joins(
          "LEFT JOIN users #{AUTHORS_JOIN_ALIAS} ON #{AUTHORS_JOIN_ALIAS}.id = topics.user_id",
        )
      end

      # Strict triage priority for the moderator dashboard: new members
      # first (this is the moment that decides whether they stay), then the
      # members who give the most feedback, oldest post breaking ties.
      def triage_sort_key(topic, score_row)
        standing = score_row ? -score_row.score : Float::INFINITY
        [new_member?(topic.user, score_row) ? 0 : 1, standing, topic.created_at]
      end

      def new_member?(user, score_row)
        score_row ? score_row.new_member? : Formula.in_grace_period?(user)
      end

      def coverage_cutoff
        SiteSetting.npn_critique_coverage_days.days.ago
      end

      def substantive_reply_params
        {
          quote_pattern: Scorer::QUOTE_PATTERN,
          min_length: SiteSetting.npn_critique_min_reply_length,
        }
      end

      private

      # Four terms, each independently tunable and each defensible out loud:
      #
      #   waiting    a topic with no substantive reply climbs the longer it
      #              waits, capped so an ancient neglected post cannot pin
      #              itself to the top forever
      #   new member a one-off boost while the author is inside the grace
      #              window
      #   recency    ordinary decay, so the feed still feels alive
      #   give-back  the author's rolling engagement score, FLOORED — it can
      #              move a topic down but never bury it, which is what keeps
      #              a quiet member visible and keeps the negative signal out
      #              of public view
      def score_sql
        <<~SQL.squish
          (
            CASE WHEN #{NO_SUBSTANTIVE_REPLY_SQL.squish}
              THEN LEAST(
                :waiting_cap,
                :waiting_per_day * (EXTRACT(EPOCH FROM (:now - topics.created_at)) / 86400.0)
              )
              ELSE 0
            END
            + CASE WHEN npn_authors.created_at > :grace_cutoff THEN :new_member_boost ELSE 0 END
            + :recency_weight * EXP(
                -0.6931471805599453
                * (EXTRACT(EPOCH FROM (:now - topics.created_at)) / 86400.0)
                / :half_life
              )
            + GREATEST(
                :reciprocity_floor,
                :reciprocity_weight * COALESCE(npn_scores.score, 0)
              )
          )
        SQL
      end

      def score_params
        substantive_reply_params.merge(
          now: Time.zone.now,
          waiting_cap: SiteSetting.npn_fair_waiting_boost_cap.to_f,
          waiting_per_day: SiteSetting.npn_fair_waiting_boost_per_day.to_f,
          grace_cutoff: SiteSetting.npn_critique_grace_period_days.days.ago,
          new_member_boost: SiteSetting.npn_fair_new_member_boost.to_f,
          recency_weight: SiteSetting.npn_fair_recency_weight.to_f,
          half_life: SiteSetting.npn_fair_recency_half_life_days.to_f,
          reciprocity_floor: SiteSetting.npn_fair_reciprocity_floor.to_f,
          reciprocity_weight: SiteSetting.npn_fair_reciprocity_weight.to_f,
        )
      end

      def sanitize(sql, params)
        ActiveRecord::Base.sanitize_sql_array([sql, params])
      end

      # Tag names travel as a bind param; the fragment shape is a constant.
      def exclude_tags(scope)
        tags = SiteSetting.npn_critique_coverage_excluded_tags.to_s.split("|")
        return scope if tags.blank?

        scope.where(<<~SQL, excluded_tags: tags)
          NOT EXISTS (
            SELECT 1
            FROM topic_tags tt
            JOIN tags excluded ON excluded.id = tt.tag_id
            WHERE tt.topic_id = topics.id AND excluded.name IN (:excluded_tags)
          )
        SQL
      end

      # Announcement topics created before the weekly-challenge plugin
      # stamped its marker only reveal themselves by title.
      def exclude_title_prefixes(scope)
        prefixes = SiteSetting.npn_critique_coverage_excluded_title_prefixes.to_s.split("|")
        return scope if prefixes.blank?

        conditions = prefixes.each_index.map { |i| "topics.title ILIKE :prefix_#{i}" }
        binds = prefixes.each_with_index.to_h { |prefix, i| [:"prefix_#{i}", "#{prefix}%"] }
        scope.where("NOT (#{conditions.join(" OR ")})", binds)
      end
    end
  end
end
