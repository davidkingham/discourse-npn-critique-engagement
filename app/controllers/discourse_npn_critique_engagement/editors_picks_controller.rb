# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The weekly editors' pick review queue: one genre tag, one Sunday-anchored
  # week, every image topic with its poster's engagement standing beside it.
  # Staff only — moderators judge image quality; this page puts the
  # give-and-take context right where the judging happens.
  class EditorsPicksController < ::ApplicationController
    requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME
    requires_login
    before_action :ensure_staff

    PICK_ACTION_CODE = "npn_editors_pick"

    # GET /critique-engagement/editors-picks?week=YYYY-MM-DD&tag=landscape
    def show
      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json do
          week_start = requested_week
          topics = week_topics(week_start)
          tags = genre_tags(topics)
          topics =
            topics.select { |topic| topic.tags.map(&:name).include?(params[:tag]) } if params[
            :tag
          ].present?

          render json: {
                   week_start: week_start,
                   tag: params[:tag].presence,
                   tags: tags,
                   topics: serialize_topics(topics),
                 }
        end
      end
    end

    # POST /critique-engagement/editors-picks/pick
    # Applies the editors-pick tag and posts a public small-action note —
    # replacing the old manual whisper — so the pick and the picker are
    # visible on the topic itself.
    def pick
      topic = Topic.find_by(id: params.require(:topic_id))
      raise Discourse::NotFound if topic.nil? || !category_ids.include?(topic.category_id)

      if topic.tags.map(&:name).include?(pick_tag)
        return(
          render_json_error(
            I18n.t("npn_critique_engagement.editors_picks.already_picked"),
            status: 422,
          )
        )
      end

      DiscourseTagging.tag_topic_by_names(topic, guardian, [pick_tag], append: true)
      topic.add_moderator_post(
        current_user,
        nil,
        post_type: Post.types[:small_action],
        action_code: PICK_ACTION_CODE,
      )

      render json: {
               picked: true,
               picked_by: {
                 username: current_user.username,
                 picked_at: Time.zone.now,
               },
             }
    end

    private

    def ensure_staff
      raise Discourse::InvalidAccess.new if !current_user&.staff?
    end

    def requested_week
      base = params[:week].present? ? Date.parse(params[:week]) : Date.current
      base.beginning_of_week(:sunday)
    rescue Date::Error
      raise Discourse::InvalidParameters.new(:week)
    end

    def week_topics(week_start)
      Topic
        .where(category_id: category_ids)
        .where(archetype: Archetype.default)
        .where(deleted_at: nil, visible: true)
        .where("topics.user_id > 0")
        .where(created_at: week_start.beginning_of_day...(week_start + 7.days).beginning_of_day)
        .includes(:tags, :user, :image_upload)
        .to_a
    end

    # The genre selector: every tag carried by the week's topics, except the
    # pick tag itself.
    def genre_tags(topics)
      topics.flat_map { |topic| topic.tags.map(&:name) }.uniq.sort - [pick_tag]
    end

    def serialize_topics(topics)
      scores = Score.where(user_id: topics.map(&:user_id).uniq).index_by(&:user_id)
      pick_notes =
        Post
          .where(topic_id: topics.map(&:id), action_code: PICK_ACTION_CODE, deleted_at: nil)
          .includes(:user)
          .order(:created_at)
          .index_by(&:topic_id)

      topics
        .map { |topic| topic_payload(topic, scores[topic.user_id], pick_notes[topic.id]) }
        .sort_by do |payload|
          [payload[:score] ? -payload[:score][:score] : Float::INFINITY, payload[:created_at]]
        end
    end

    def topic_payload(topic, score, pick_note)
      {
        id: topic.id,
        title: topic.title,
        url: topic.relative_url,
        image_url: topic.image_url,
        created_at: topic.created_at,
        username: topic.user&.username,
        name: topic.user&.name,
        avatar_template: topic.user&.avatar_template,
        score:
          score &&
            {
              score: score.score.round,
              tier: score.tier,
              topics_replied: score.topics_replied,
              created_topics: score.created_topics,
              ratio: score.ratio.round(2),
            },
        picked: topic.tags.map(&:name).include?(pick_tag),
        picked_by:
          pick_note && { username: pick_note.user&.username, picked_at: pick_note.created_at },
      }
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
