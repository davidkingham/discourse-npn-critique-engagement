# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The numbers that actually say whether the fair feed worked.
  #
  # Reply *counts* can climb while the same thirty people talk to each other —
  # that is the echo chamber, and it looks like health if you only count
  # activity. These four weekly series measure reach instead:
  #
  #   distinct_replied_to     how many distinct members got a substantive
  #                           critique that week (the echo-chamber number:
  #                           people reached, not replies made)
  #   answered_within_48h     of the topics posted that week, how many got a
  #                           first substantive critique within 48 hours
  #   critiques_to_non_core   of the critiques given that week, how many went
  #                           to someone outside the most-active core
  #   non_critique_*          topic and reply volume outside the critique tree,
  #                           to see whether the discussion lane and the weekly
  #                           prompt move discussions
  #
  # Everything is computed live from posts and topics, so there is no table to
  # migrate and no backfill to run — the history is simply always there.
  module ReachMetrics
    # A reply counts only if it is substantive by the scorer's definition, so
    # these numbers can't drift from the score everything else is built on.
    SUBSTANTIVE_REPLY = <<~SQL
      p.post_number > 1
      AND p.post_type = 1
      AND p.deleted_at IS NULL
      AND p.user_id > 0
      AND p.user_id <> t.user_id
      AND LENGTH(REGEXP_REPLACE(p.raw, :quote_pattern, '', 'gi')) >= :min_length
    SQL

    module_function

    def weekly(weeks: 12)
      cats = FairRanking.category_ids
      return [] if cats.blank?

      since = weeks.to_i.weeks.ago.beginning_of_week
      by_week = Hash.new { |hash, key| hash[key] = empty_row(key) }

      distinct_replied_to(cats, since).each do |week, count|
        by_week[week][:distinct_replied_to] = count
      end
      answered_within_48h(cats, since).each do |week, total, within|
        by_week[week][:topics_posted] = total
        by_week[week][:answered_within_48h] = within
      end
      critiques_to_non_core(cats, since).each do |week, total, non_core|
        by_week[week][:critiques_given] = total
        by_week[week][:critiques_to_non_core] = non_core
      end
      non_critique_volume(cats, since).each do |week, topics, replies|
        by_week[week][:non_critique_topics] = topics
        by_week[week][:non_critique_replies] = replies
      end

      by_week.values.sort_by { |row| row[:week] }.reverse
    end

    def empty_row(week)
      {
        week: week,
        distinct_replied_to: 0,
        topics_posted: 0,
        answered_within_48h: 0,
        critiques_given: 0,
        critiques_to_non_core: 0,
        non_critique_topics: 0,
        non_critique_replies: 0,
      }
    end

    # Distinct topic authors who received a substantive critique in the week —
    # keyed by the reply's week, since that is when the reach happened.
    def distinct_replied_to(cats, since)
      rows = DB.query_array(<<~SQL, params(cats, since))
        SELECT date_trunc('week', p.created_at), COUNT(DISTINCT t.user_id)
        FROM posts p
        JOIN topics t ON t.id = p.topic_id
        WHERE t.category_id IN (:cats)
          AND t.deleted_at IS NULL
          AND #{SUBSTANTIVE_REPLY}
          AND p.created_at >= :since
        GROUP BY 1
      SQL
      rows.map { |week, count| [week.to_date, count.to_i] }
    end

    # Topics cohorted by the week they were posted, and how many had a
    # substantive critique within 48 hours of posting.
    def answered_within_48h(cats, since)
      rows = DB.query_array(<<~SQL, params(cats, since))
        SELECT
          date_trunc('week', t.created_at),
          COUNT(*),
          COUNT(*) FILTER (
            WHERE fr.first_reply_at IS NOT NULL
              AND fr.first_reply_at <= t.created_at + INTERVAL '48 hours'
          )
        FROM topics t
        LEFT JOIN LATERAL (
          SELECT MIN(p.created_at) AS first_reply_at
          FROM posts p
          WHERE p.topic_id = t.id AND #{SUBSTANTIVE_REPLY}
        ) fr ON TRUE
        WHERE t.category_id IN (:cats)
          AND t.archetype = 'regular'
          AND t.deleted_at IS NULL
          AND t.visible
          AND t.user_id > 0
          AND t.created_at >= :since
        GROUP BY 1
      SQL
      rows.map { |week, total, within| [week.to_date, total.to_i, within.to_i] }
    end

    # Of the critiques given in a week, how many went to an author outside the
    # active core. The core is the current top decile by weighted_replies — a
    # present-day snapshot applied across the series, since the core is fairly
    # stable and there is no per-week standing to reconstruct.
    def critiques_to_non_core(cats, since)
      binds = params(cats, since).merge(core: core_user_ids.presence || [-1])
      rows = DB.query_array(<<~SQL, binds)
        SELECT
          date_trunc('week', p.created_at),
          COUNT(*),
          COUNT(*) FILTER (WHERE t.user_id NOT IN (:core))
        FROM posts p
        JOIN topics t ON t.id = p.topic_id
        WHERE t.category_id IN (:cats)
          AND t.deleted_at IS NULL
          AND #{SUBSTANTIVE_REPLY}
          AND p.created_at >= :since
        GROUP BY 1
      SQL
      rows.map { |week, total, non_core| [week.to_date, total.to_i, non_core.to_i] }
    end

    # Topic and reply volume outside the critique tree, so the effect of the
    # discussion lane and the weekly prompt is visible next to the rest.
    def non_critique_volume(cats, since)
      topic_rows = DB.query_array(<<~SQL, params(cats, since))
        SELECT date_trunc('week', t.created_at), COUNT(*)
        FROM topics t
        WHERE t.category_id NOT IN (:cats)
          AND t.archetype = 'regular'
          AND t.deleted_at IS NULL
          AND t.visible
          AND t.user_id > 0
          AND t.created_at >= :since
        GROUP BY 1
      SQL
      topics = topic_rows.to_h { |week, count| [week.to_date, count.to_i] }

      reply_rows = DB.query_array(<<~SQL, params(cats, since))
        SELECT date_trunc('week', p.created_at), COUNT(*)
        FROM posts p
        JOIN topics t ON t.id = p.topic_id
        WHERE t.category_id NOT IN (:cats)
          AND t.deleted_at IS NULL
          AND p.post_number > 1
          AND p.post_type = 1
          AND p.deleted_at IS NULL
          AND p.user_id > 0
          AND p.created_at >= :since
        GROUP BY 1
      SQL
      replies = reply_rows.to_h { |week, count| [week.to_date, count.to_i] }

      (topics.keys | replies.keys).map { |week| [week, topics[week] || 0, replies[week] || 0] }
    end

    # The active core: the top decile of scored members by how much critique
    # they give. Empty until there are at least ten scored members, so a tiny
    # community isn't split into "core" and "everyone else" on noise.
    def core_user_ids
      total = Score.count
      return [] if total < 10

      take = [(total / 10.0).ceil, 1].max
      Score.order(weighted_replies: :desc).limit(take).pluck(:user_id)
    end

    def params(cats, since)
      {
        cats: cats,
        since: since,
        quote_pattern: Scorer::QUOTE_PATTERN,
        min_length: SiteSetting.npn_critique_min_reply_length,
      }
    end
  end
end
