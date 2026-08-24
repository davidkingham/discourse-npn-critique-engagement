# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Reworked images: the photographer posted an updated image in their own
  # thread after someone else critiqued it. That loop — critique in, revised
  # photo out — is the most on-mission thing the community produces, and it
  # is invisible to every surface keyed on topic creation date: the topic is
  # old news by the time the rework lands. This finds those threads so the
  # dashboard can show them and the pick queue can include them.
  module Reworks
    extend self

    # {topic_id => {reworked_at:, post_number:}} — topics whose author posted
    # an image reply at or after the cutoff, with at least one earlier reply
    # from someone else (an image reposted before any critique isn't a
    # rework). The newest qualifying post wins, so the link lands on the
    # latest version.
    def since(category_ids, cutoff)
      return {} if category_ids.blank?

      rows = DB.query(<<~SQL, category_ids: category_ids, cutoff: cutoff)
        SELECT p.topic_id,
               MAX(p.created_at) AS reworked_at,
               (ARRAY_AGG(p.post_number ORDER BY p.created_at DESC))[1] AS post_number
        FROM posts p
        JOIN topics t ON t.id = p.topic_id
        WHERE t.category_id IN (:category_ids)
          AND t.archetype = 'regular'
          AND t.deleted_at IS NULL
          AND t.visible
          AND t.user_id > 0
          AND p.user_id = t.user_id
          AND p.post_number > 1
          AND p.deleted_at IS NULL
          AND p.post_type = 1
          AND p.image_upload_id IS NOT NULL
          AND p.created_at >= :cutoff
          AND EXISTS (
            SELECT 1
            FROM posts r
            WHERE r.topic_id = p.topic_id
              AND r.post_number > 1
              AND r.deleted_at IS NULL
              AND r.post_type = 1
              AND r.user_id > 0
              AND r.user_id <> t.user_id
              AND r.created_at < p.created_at
          )
        GROUP BY p.topic_id
      SQL

      rows.to_h do |row|
        [row.topic_id, { reworked_at: row.reworked_at, post_number: row.post_number }]
      end
    end
  end
end
