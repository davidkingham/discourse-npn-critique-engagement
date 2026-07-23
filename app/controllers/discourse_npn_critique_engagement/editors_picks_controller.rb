# frozen_string_literal: true

# Referenced in the class body below, and this file can be autoloaded during
# migrations before after_initialize has required the libs.
require_relative "../../../lib/discourse_npn_critique_engagement/editors_pick"

module DiscourseNpnCritiqueEngagement
  # The weekly editors' pick review queue: one genre tag, one Sunday-anchored
  # week, every image topic with its poster's engagement standing beside it.
  # Staff only — moderators judge image quality; this page puts the
  # give-and-take context right where the judging happens.
  class EditorsPicksController < ::ApplicationController
    requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME
    requires_login
    before_action :ensure_staff

    PICK_ACTION_CODE = EditorsPick::ACTION_CODE
    PICK_GENRE_FIELD = EditorsPick::GENRE_FIELD
    REASON_MAX_LENGTH = 1000

    # GET /critique-engagement/editors-picks?week=YYYY-MM-DD&tag=landscape
    def show
      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json do
          week_start = requested_week
          topics = week_topics(week_start)
          tags = GenreTags.all
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

    # GET /moderate/outreach and /moderate/report
    # HTML shell only — the Ember routes fetch their data from the staff JSON
    # endpoints under /admin/plugins/critique-engagement.
    def page_shell
      render html: nil, layout: true
    end

    # POST /critique-engagement/editors-picks/pick
    # Genres overlap on cross-tagged images, so the moderator declares which
    # genre the pick fills (stored on the note for the other moderators), and
    # can say why publicly — the reason becomes the note's body. With a
    # finalize window configured the pick is only STAGED: nothing member-
    # visible happens until the delayed job fires, so an accidental or
    # regretted pick can be undone without the member ever knowing.
    def pick
      topic = Topic.find_by(id: params.require(:topic_id))
      raise Discourse::NotFound if topic.nil? || !category_ids.include?(topic.category_id)

      if EditorsPick.picked?(topic) || PendingPick.exists?(topic_id: topic.id)
        return(
          render_json_error(
            I18n.t("npn_critique_engagement.editors_picks.already_picked"),
            status: 422,
          )
        )
      end

      genre = params[:genre].presence
      if genre.present? && !genre_options(topic).include?(genre)
        raise Discourse::InvalidParameters.new(:genre)
      end
      reason = params[:reason].to_s.strip.presence
      raise Discourse::InvalidParameters.new(:reason) if reason && reason.length > REASON_MAX_LENGTH

      window = SiteSetting.npn_critique_pick_finalize_minutes
      if window == 0
        EditorsPick.finalize!(topic: topic, moderator: current_user, genre: genre, reason: reason)
        render json: {
                 picked: true,
                 picked_by: {
                   username: current_user.username,
                   picked_at: Time.zone.now,
                   genre: genre,
                 },
               }
      else
        pending =
          PendingPick.create!(
            topic_id: topic.id,
            user_id: current_user.id,
            genre: genre,
            reason: reason,
            finalize_at: window.minutes.from_now,
          )
        Jobs.enqueue_in(window.minutes, :npn_finalize_editors_pick, pending_pick_id: pending.id)
        render json: {
                 pending: {
                   username: current_user.username,
                   finalize_at: pending.finalize_at,
                   genre: genre,
                 },
               }
      end
    end

    # POST /moderate/editors-picks/no-pick
    # The deliberate empty slot: a moderator judged the genre's images for
    # the week and found nothing strong enough. On the dashboard board this
    # reads differently from a slot nobody has gotten to yet. Resets with
    # the pick week on Sunday, like picks themselves.
    def no_pick
      genre = params.require(:genre)
      raise Discourse::InvalidParameters.new(:genre) if !GenreTags.all.include?(genre)

      declaration =
        NoPick.current_week.find_by(genre: genre) ||
          NoPick.create!(genre: genre, user: current_user)

      render json: { genre: genre, username: declaration.user&.username }
    end

    # DELETE /moderate/editors-picks/no-pick
    def undo_no_pick
      NoPick.current_week.where(genre: params.require(:genre)).destroy_all

      head :no_content
    end

    # POST /critique-engagement/editors-picks/unpick
    # Two tools in one: cancelling a staged pick (nothing public ever
    # happened, the member never knows) and removing a finalized pick (tag,
    # note, and badge are removed; a PM that already went out stays).
    def unpick
      topic = Topic.find_by(id: params.require(:topic_id))
      raise Discourse::NotFound if topic.nil? || !category_ids.include?(topic.category_id)

      if (pending = PendingPick.find_by(topic_id: topic.id))
        pending.destroy!
        return render json: { picked: false }
      end

      if EditorsPick.picked?(topic)
        EditorsPick.remove!(topic: topic, moderator: current_user)
        return render json: { picked: false }
      end

      render_json_error(I18n.t("npn_critique_engagement.editors_picks.not_picked"), status: 422)
    end

    private

    def ensure_staff
      raise Discourse::InvalidAccess.new if !current_user&.staff?
    end

    # Picks are judged after a week completes, so without an explicit week
    # the queue opens on the last finished week — mods pick on Sunday, when
    # the just-started week would be empty.
    def requested_week
      if params[:week].present?
        Date.parse(params[:week]).beginning_of_week(:sunday)
      else
        Date.current.beginning_of_week(:sunday) - 7
      end
    rescue Date::Error
      raise Discourse::InvalidParameters.new(:week)
    end

    def week_topics(week_start)
      scope =
        Topic
          .where(category_id: category_ids)
          .where(archetype: Archetype.default)
          .where(deleted_at: nil, visible: true)
          .where("topics.user_id > 0")
          .where(created_at: week_start.beginning_of_day...(week_start + 7.days).beginning_of_day)
          .where(
            "NOT EXISTS (SELECT 1 FROM topic_custom_fields tcf
             WHERE tcf.topic_id = topics.id AND tcf.name = 'npn_weekly_challenge_slug')",
          )

      # Weekly-challenge ANNOUNCEMENT topics aren't pickable images — the
      # marker field catches ones the weekly-challenge plugin created, the
      # title prefixes catch older ones from before the marker existed.
      # Challenge ENTRIES stay in the queue.
      excluded_title_prefixes.each do |prefix|
        scope = scope.where("topics.title NOT ILIKE ?", "#{prefix}%")
      end

      scope.includes(:tags, :user, :image_upload).to_a
    end

    def excluded_title_prefixes
      SiteSetting.npn_critique_coverage_excluded_title_prefixes.to_s.split("|")
    end

    def serialize_topics(topics)
      scores = Score.where(user_id: topics.map(&:user_id).uniq).index_by(&:user_id)
      pick_notes =
        Post
          .where(topic_id: topics.map(&:id), action_code: PICK_ACTION_CODE, deleted_at: nil)
          .includes(:user)
          .order(:created_at)
          .index_by(&:topic_id)
      note_genres =
        PostCustomField
          .where(post_id: pick_notes.values.map(&:id), name: PICK_GENRE_FIELD)
          .pluck(:post_id, :value)
          .to_h
      pendings = PendingPick.for_topics(topics.map(&:id))
      recent_picks = EditorsPick.pick_counts_for_users(topics.map(&:user_id).uniq)

      topics
        .map do |topic|
          topic_payload(
            topic,
            scores[topic.user_id],
            pick_notes[topic.id],
            note_genres,
            pendings,
            recent_picks[topic.user_id].to_i,
          )
        end
        .sort_by do |payload|
          [payload[:score] ? -payload[:score][:score] : Float::INFINITY, payload[:created_at]]
        end
    end

    def topic_payload(topic, score, pick_note, note_genres = {}, pendings = {}, recent_picks = 0)
      pending = pendings[topic.id]
      {
        id: topic.id,
        title: topic.title,
        url: topic.relative_url,
        image_url: topic.image_url,
        created_at: topic.created_at,
        username: topic.user&.username,
        name: topic.user&.name,
        avatar_template: topic.user&.avatar_template,
        recent_picks: recent_picks,
        score:
          score &&
            {
              score: score.score.round,
              tier: score.tier,
              topics_replied: score.topics_replied,
              created_topics: score.created_topics,
              ratio: score.ratio.round(2),
            },
        genre_options: genre_options(topic),
        pending:
          pending &&
            {
              username: pending.user&.username,
              finalize_at: pending.finalize_at,
              genre: pending.genre,
            },
        picked: topic.tags.map(&:name).include?(pick_tag),
        picked_by:
          pick_note &&
            {
              username: pick_note.user&.username,
              picked_at: pick_note.created_at,
              genre: note_genres[pick_note.id],
            },
      }
    end

    # The genres this image could fill a pick slot for: its own tags, minus
    # the pick tag and the style/attribute tags that aren't pick genres.
    def genre_options(topic)
      topic.tags.map(&:name).sort - GenreTags.non_genre_tags
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
