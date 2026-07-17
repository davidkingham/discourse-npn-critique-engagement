# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The genre vocabulary: every tag except the editors-pick tag and the
  # style/attribute tags excluded from the pick board. Also answers "which
  # genres does this member post to?" so outreach lands with the moderator
  # who knows their work.
  module GenreTags
    extend self

    def pick_tag
      SiteSetting.npn_critique_editors_pick_tag.to_s.split("|").first.presence || "editors-pick"
    end

    def non_genre_tags
      [pick_tag] + SiteSetting.npn_critique_pick_excluded_tags.to_s.split("|")
    end

    # {user_id => [{tag:, count:}, ...]} — each member's most-posted genre
    # tags within the rolling window, best first.
    def top_for_users(user_ids, limit: 3)
      return {} if user_ids.blank? || category_ids.blank?

      rows = DB.query(<<~SQL, params(user_ids))
        SELECT t.user_id, tags.name AS tag, COUNT(*) AS topics
        FROM topics t
        JOIN topic_tags tt ON tt.topic_id = t.id
        JOIN tags ON tags.id = tt.tag_id
        WHERE t.user_id IN (:user_ids)
          AND t.category_id IN (:category_ids)
          AND t.archetype = 'regular'
          AND t.deleted_at IS NULL
          AND t.created_at >= :window_start
          AND tags.name NOT IN (:non_genre_tags)
        GROUP BY t.user_id, tags.name
        ORDER BY t.user_id, COUNT(*) DESC, tags.name
      SQL

      rows
        .group_by(&:user_id)
        .transform_values do |user_rows|
          user_rows.first(limit).map { |row| { tag: row.tag, count: row.topics } }
        end
    end

    private

    def params(user_ids)
      {
        user_ids: user_ids,
        category_ids: category_ids,
        window_start: SiteSetting.npn_critique_window_days.days.ago,
        non_genre_tags: non_genre_tags,
      }
    end

    def category_ids
      if (category_id = SiteSetting.npn_critique_category.presence&.to_i)
        Category.where("id = :id OR parent_category_id = :id", id: category_id).pluck(:id)
      else
        []
      end
    end
  end
end
