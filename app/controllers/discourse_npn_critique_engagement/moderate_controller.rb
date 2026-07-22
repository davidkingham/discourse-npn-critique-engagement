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

    # Topics still waiting for a substantive critique. The candidate
    # definition lives in FairRanking so this queue and the member-facing
    # feed can never disagree about what "still waiting" means; the ordering
    # stays triage order, because a moderator works this list top-down and
    # wants strict priority rather than the feed's round-robin.
    def coverage
      topics =
        FairRanking
          .candidates
          .includes(:user, :image_upload, :tags)
          .reject { |topic| topic.user.nil? }
      scores = Score.where(user_id: topics.map(&:user_id).uniq).index_by(&:user_id)

      sorted = topics.sort_by { |topic| FairRanking.triage_sort_key(topic, scores[topic.user_id]) }

      {
        total: sorted.size,
        topics:
          sorted
            .first(COVERAGE_LIMIT)
            .map { |topic| coverage_payload(topic, scores[topic.user_id]) },
      }
    end

    def new_member?(user, score_row)
      FairRanking.new_member?(user, score_row)
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
        tags: topic.tags.map(&:name).sort - [pick_tag],
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

    # One row per genre tag in play: has a pick been MADE since the week
    # began? Moderators pick at week's end for the week that just closed, so
    # the board keys on when the pick happened — not on when the image was
    # posted — and resets every Sunday.
    def pick_status
      return [] if category_ids.blank?

      # The pick pool — this week's and last week's images — supplies the
      # genre vocabulary; a pick for an even older image still shows via its
      # declared genre below.
      pool =
        Topic
          .where(category_id: category_ids)
          .where(archetype: Archetype.default)
          .where(deleted_at: nil, visible: true)
          .where("topics.user_id > 0")
          .where(created_at: (week_start - 7.days).beginning_of_day..)
          .includes(:tags)
          .to_a

      events = pick_events
      # A moderator can declare "no pick this week" for a genre — a judged
      # empty slot, not a neglected one. Shown unless an actual pick
      # supersedes it.
      no_picks =
        NoPick
          .since(week_start.beginning_of_day)
          .includes(:user)
          .order(:created_at)
          .group_by(&:genre)
      tags =
        (genre_tags(pool) + events.filter_map { |event| event[:genre] } + no_picks.keys).uniq.sort -
          excluded_pick_tags

      tags.map do |tag|
        # A pick declared for a genre fills only that genre's slot — tags
        # overlap, the declaration doesn't. Picks made before genres were
        # recorded fall back to counting for every genre they're tagged with.
        event =
          events.find do |candidate|
            if candidate[:genre]
              candidate[:genre] == tag
            else
              candidate[:topic_tags].include?(tag)
            end
          end
        no_pick = event.nil? ? no_picks[tag]&.first : nil

        {
          tag: tag,
          picked: event.present?,
          picked_by: event&.dig(:username),
          topic_url: event&.dig(:topic_url),
          no_pick: no_pick && { username: no_pick.user&.username },
        }
      end
    end

    # Every pick made since Sunday — finalized notes and staged picks in
    # their undo window alike (a staged pick must already fill its genre slot
    # so nobody double-picks it).
    def pick_events
      week_cutoff = week_start.beginning_of_day

      notes =
        Post
          .joins(:topic)
          .where(topics: { category_id: category_ids, deleted_at: nil })
          .where(action_code: EditorsPick::ACTION_CODE, deleted_at: nil)
          .where(created_at: week_cutoff..)
          .includes(:user, topic: :tags)
          .order(:created_at)
          .to_a
      note_genres =
        PostCustomField
          .where(post_id: notes.map(&:id), name: EditorsPick::GENRE_FIELD)
          .pluck(:post_id, :value)
          .to_h

      pendings =
        PendingPick
          .joins(:topic)
          .where(topics: { category_id: category_ids, deleted_at: nil })
          .where(created_at: week_cutoff..)
          .includes(:user, topic: :tags)

      (notes + pendings.to_a).map do |record|
        note = record.is_a?(Post)
        {
          username: record.user&.username,
          genre: note ? note_genres[record.id] : record.genre,
          topic_tags: record.topic.tags.map(&:name),
          topic_url: record.topic.relative_url,
        }
      end
    end

    def genre_tags(topics)
      topics.flat_map { |topic| topic.tags.map(&:name) }.uniq.sort - [pick_tag] - excluded_pick_tags
    end

    def excluded_pick_tags
      SiteSetting.npn_critique_pick_excluded_tags.to_s.split("|")
    end

    def mini_rows(scope)
      rows = scope.includes(:user).limit(MINI_LIST_LIMIT).reject { |row| row.user.nil? }
      serialize_data(
        rows,
        ReportRowSerializer,
        outreach_logs: OutreachLog.latest_for(rows.map(&:user_id)),
        claims: OutreachClaim.active_for(rows.map(&:user_id)),
      )
    end

    def week_start
      @week_start ||= Date.current.beginning_of_week(:sunday)
    end

    def pick_tag
      SiteSetting.npn_critique_editors_pick_tag.to_s.split("|").first.presence || "editors-pick"
    end

    def category_ids
      @category_ids ||= FairRanking.category_ids
    end
  end
end
