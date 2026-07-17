# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The moderator dashboard: everything a moderator triages, on one page.
  # Images still waiting for a critique (new members first — miss them and
  # they never come back), this week's pick status per genre, and the top of
  # the outreach and welcome queues.
  class ModerateController < ::ApplicationController
    requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME
    requires_login
    before_action :ensure_staff

    COVERAGE_LIMIT = 20
    MINI_LIST_LIMIT = 5

    # GET /critique-engagement/moderate
    def show
      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json do
          render json: {
                   coverage: coverage,
                   new_members: new_members,
                   pick_status: pick_status,
                   week_start: week_start,
                   outreach: mini_rows(Score.where(tier: :priority_outreach).order(score: :asc)),
                   welcome:
                     mini_rows(
                       Score
                         .where(tier: :new_member)
                         .where("weighted_replies > 0")
                         .order(weighted_replies: :desc),
                     ),
                 }
        end
      end
    end

    private

    def ensure_staff
      raise Discourse::InvalidAccess.new if !current_user&.staff?
    end

    # Topics still waiting for a substantive critique (the scorer's own
    # definition: 100+ characters after quote-stripping, from someone other
    # than the poster).
    def coverage
      return { total: 0, topics: [] } if category_ids.blank?

      topic_ids = DB.query_single(<<~SQL, coverage_params)
        SELECT t.id
        FROM topics t
        WHERE t.category_id IN (:category_ids)
          AND t.archetype = 'regular'
          AND t.deleted_at IS NULL
          AND t.visible
          AND t.user_id > 0
          AND t.created_at >= :cutoff
          AND NOT EXISTS (
            SELECT 1
            FROM posts p
            WHERE p.topic_id = t.id
              AND p.post_number > 1
              AND p.deleted_at IS NULL
              AND p.post_type = 1
              AND p.user_id > 0
              AND p.user_id <> t.user_id
              AND LENGTH(REGEXP_REPLACE(p.raw, :quote_pattern, '', 'gi')) >= :min_length
          )
          #{coverage_excluded_tags_fragment}
      SQL

      topics =
        Topic.where(id: topic_ids).includes(:user, :image_upload).reject { |topic| topic.user.nil? }
      scores = Score.where(user_id: topics.map(&:user_id).uniq).index_by(&:user_id)

      sorted = topics.sort_by { |topic| coverage_sort_key(topic, scores[topic.user_id]) }

      {
        total: sorted.size,
        topics:
          sorted
            .first(COVERAGE_LIMIT)
            .map { |topic| coverage_payload(topic, scores[topic.user_id]) },
      }
    end

    # New members outrank everything — this is the moment that decides
    # whether they stay. After that, the members who give the most feedback
    # deserve it back first; oldest post breaks ties.
    def coverage_sort_key(topic, score_row)
      new_member = new_member?(topic.user, score_row)
      standing = score_row ? -score_row.score : Float::INFINITY
      [new_member ? 0 : 1, standing, topic.created_at]
    end

    def new_member?(user, score_row)
      score_row ? score_row.new_member? : Formula.in_grace_period?(user)
    end

    def coverage_payload(topic, score_row)
      {
        id: topic.id,
        title: topic.title,
        url: topic.relative_url,
        image_url: topic.image_url,
        created_at: topic.created_at,
        username: topic.user.username,
        avatar_template: topic.user.avatar_template,
        tier: score_row&.tier || (new_member?(topic.user, score_row) ? "new_member" : nil),
        score: score_row&.score&.round,
        new_member: new_member?(topic.user, score_row),
      }
    end

    # Posts in the New Members category tree that haven't collected enough
    # replies yet. It's a separate category that moderators miss, and every
    # new member deserves more than one response — so posts stay on the list
    # until they reach the configured reply count, fewest replies first.
    def new_members
      return { total: 0, topics: [] } if new_member_category_ids.blank?

      rows = DB.query(<<~SQL, new_member_params)
        SELECT t.id, COUNT(p.id) AS replies
        FROM topics t
        LEFT JOIN posts p
          ON p.topic_id = t.id
          AND p.post_number > 1
          AND p.deleted_at IS NULL
          AND p.post_type = 1
          AND p.user_id > 0
          AND p.user_id <> t.user_id
        WHERE t.category_id IN (:category_ids)
          AND t.archetype = 'regular'
          AND t.deleted_at IS NULL
          AND t.visible
          AND t.user_id > 0
          AND t.created_at >= :cutoff
        GROUP BY t.id
        HAVING COUNT(p.id) < :min_replies
      SQL

      reply_counts = rows.to_h { |row| [row.id, row.replies] }
      topics =
        Topic
          .where(id: reply_counts.keys)
          .includes(:user, :image_upload, :category)
          .reject { |topic| topic.user.nil? }
          .sort_by { |topic| [reply_counts[topic.id], topic.created_at] }

      {
        total: topics.size,
        topics:
          topics
            .first(COVERAGE_LIMIT)
            .map do |topic|
              {
                id: topic.id,
                title: topic.title,
                url: topic.relative_url,
                image_url: topic.image_url,
                created_at: topic.created_at,
                username: topic.user.username,
                avatar_template: topic.user.avatar_template,
                subcategory: topic.category&.name,
                replies: reply_counts[topic.id],
              }
            end,
      }
    end

    def new_member_params
      {
        category_ids: new_member_category_ids,
        cutoff: SiteSetting.npn_critique_coverage_days.days.ago,
        min_replies: SiteSetting.npn_critique_new_member_min_replies,
      }
    end

    def new_member_category_ids
      @new_member_category_ids ||=
        if (category_id = SiteSetting.npn_critique_new_member_category.presence&.to_i)
          Category.where("id = :id OR parent_category_id = :id", id: category_id).pluck(:id)
        else
          []
        end
    end

    # One row per genre tag active this week: has it received a pick yet,
    # and from whom?
    def pick_status
      return [] if category_ids.blank?

      topics =
        Topic
          .where(category_id: category_ids)
          .where(archetype: Archetype.default)
          .where(deleted_at: nil, visible: true)
          .where("topics.user_id > 0")
          .where(created_at: week_start.beginning_of_day..)
          .includes(:tags)
          .to_a

      picked_topic_ids =
        topics.select { |topic| topic.tags.map(&:name).include?(pick_tag) }.map(&:id)
      pick_notes =
        Post
          .where(
            topic_id: picked_topic_ids,
            action_code: EditorsPicksController::PICK_ACTION_CODE,
            deleted_at: nil,
          )
          .includes(:user)
          .order(:created_at)
          .index_by(&:topic_id)

      genre_tags(topics).map do |tag|
        tagged = topics.select { |topic| topic.tags.map(&:name).include?(tag) }
        picked = tagged.find { |topic| picked_topic_ids.include?(topic.id) }
        note = picked && pick_notes[picked.id]

        {
          tag: tag,
          picked: picked.present?,
          picked_by: note&.user&.username,
          topic_url: picked&.relative_url,
        }
      end
    end

    def genre_tags(topics)
      topics.flat_map { |topic| topic.tags.map(&:name) }.uniq.sort - [pick_tag] - excluded_pick_tags
    end

    def excluded_pick_tags
      SiteSetting.npn_critique_pick_excluded_tags.to_s.split("|")
    end

    # Weekly-challenge threads (and anything else listed) don't need critique
    # coverage. The fragment is a trusted constant shape; tag names travel as
    # a bind param.
    def coverage_excluded_tags_fragment
      return "" if coverage_excluded_tags.blank?

      <<~SQL
        AND NOT EXISTS (
          SELECT 1
          FROM topic_tags tt
          JOIN tags excluded ON excluded.id = tt.tag_id
          WHERE tt.topic_id = t.id AND excluded.name IN (:excluded_tags)
        )
      SQL
    end

    def coverage_excluded_tags
      SiteSetting.npn_critique_coverage_excluded_tags.to_s.split("|")
    end

    def mini_rows(scope)
      rows = scope.includes(:user).limit(MINI_LIST_LIMIT).reject { |row| row.user.nil? }
      serialize_data(
        rows,
        ReportRowSerializer,
        outreach_logs: OutreachLog.latest_for(rows.map(&:user_id)),
      )
    end

    def coverage_params
      params = {
        category_ids: category_ids,
        cutoff: SiteSetting.npn_critique_coverage_days.days.ago,
        quote_pattern: Scorer::QUOTE_PATTERN,
        min_length: SiteSetting.npn_critique_min_reply_length,
      }
      params[:excluded_tags] = coverage_excluded_tags if coverage_excluded_tags.present?
      params
    end

    def week_start
      @week_start ||= Date.current.beginning_of_week(:sunday)
    end

    def pick_tag
      SiteSetting.npn_critique_editors_pick_tag.to_s.split("|").first.presence || "editors-pick"
    end

    def category_ids
      @category_ids ||=
        if (category_id = SiteSetting.npn_critique_category.presence&.to_i)
          Category.where("id = :id OR parent_category_id = :id", id: category_id).pluck(:id)
        else
          []
        end
    end
  end
end
