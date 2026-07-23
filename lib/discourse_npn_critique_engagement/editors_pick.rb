# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Everything that makes a pick real — the tag, the public note (carrying
  # the declared genre and the moderator's reason), the post-tied badge, and
  # the congratulations PM — and the reverse of it. Finalization runs from
  # the controller (instant picks), the delayed job (staged picks), and the
  # nightly sweep (lost jobs), so it lives here rather than in any of them.
  module EditorsPick
    extend self

    ACTION_CODE = "npn_editors_pick"
    GENRE_FIELD = "npn_editors_pick_genre"

    def finalize!(topic:, moderator:, genre: nil, reason: nil)
      return if topic.nil? || moderator.nil? || picked?(topic)

      DiscourseTagging.tag_topic_by_names(
        topic,
        moderator.guardian,
        [GenreTags.pick_tag],
        append: true,
      )
      note =
        topic.add_moderator_post(
          moderator,
          reason,
          post_type: Post.types[:small_action],
          action_code: ACTION_CODE,
        )
      if genre && note
        note.custom_fields[GENRE_FIELD] = genre
        note.save_custom_fields
      end
      grant_badge(topic, moderator)
      send_pm(topic)
    end

    # The late-correction tool: removes the tag, the public note, and the
    # badge. A congratulations PM that already went out stays — it can't be
    # unsent, only the record gets corrected.
    def remove!(topic:, moderator:)
      remaining = topic.tags.map(&:name) - [GenreTags.pick_tag]
      DiscourseTagging.tag_topic_by_names(topic, moderator.guardian, remaining)
      notes(topic).each { |note| PostDestroyer.new(moderator, note).destroy }
      revoke_badge(topic, moderator)
    end

    def finalize_due!
      PendingPick.due.find_each do |pending|
        topic = Topic.find_by(id: pending.topic_id, deleted_at: nil)
        moderator = User.find_by(id: pending.user_id)
        if topic && moderator
          finalize!(
            topic: topic,
            moderator: moderator,
            genre: pending.genre,
            reason: pending.reason,
          )
        end
        pending.destroy!
      rescue => e
        Rails.logger.warn(
          "NPN critique engagement: finalizing pick #{pending.id} failed: #{e.message}",
        )
      end
    end

    def picked?(topic)
      topic.tags.map(&:name).include?(GenreTags.pick_tag)
    end

    def notes(topic)
      Post.where(topic_id: topic.id, action_code: ACTION_CODE, deleted_at: nil)
    end

    # {user_id => count} — how many of each member's topics are editors'
    # picks made in the trailing window (default 12 months). Moderators use
    # recent pick frequency as a selection signal on the review page, so it
    # rides along with each candidate. Counted by when the pick tag was
    # applied (topic_tags.created_at), which is when the pick was made;
    # unpicking removes the tag, so removed picks drop out on their own.
    def pick_counts_for_users(user_ids, since: 12.months.ago)
      return {} if user_ids.blank?

      DB
        .query(<<~SQL, user_ids: user_ids, pick_tag: GenreTags.pick_tag, since: since)
          SELECT t.user_id, COUNT(DISTINCT t.id) AS picks
          FROM topics t
          JOIN topic_tags tt ON tt.topic_id = t.id
          JOIN tags ON tags.id = tt.tag_id
          WHERE t.user_id IN (:user_ids)
            AND t.deleted_at IS NULL
            AND tags.name = :pick_tag
            AND tt.created_at >= :since
          GROUP BY t.user_id
        SQL
        .to_h { |row| [row.user_id, row.picks] }
    end

    private

    # The badge honors the photographer, not just the post — granted by the
    # picking moderator and tied to the image, so the badge page becomes a
    # gallery of every pick.
    def grant_badge(topic, moderator)
      return if SiteSetting.npn_critique_editors_pick_badge_name.blank?
      return if topic.user.nil?

      BadgeGranter.grant(
        Badges.editors_pick,
        topic.user,
        granted_by: moderator,
        post_id: topic.first_post&.id,
      )
    rescue => e
      Rails.logger.warn("NPN critique engagement: editors pick badge failed: #{e.message}")
    end

    def revoke_badge(topic, moderator)
      return if SiteSetting.npn_critique_editors_pick_badge_name.blank?
      return if topic.user.nil?

      badge = Badge.find_by(name: SiteSetting.npn_critique_editors_pick_badge_name)
      return if badge.nil?

      user_badge =
        UserBadge.find_by(badge_id: badge.id, user_id: topic.user_id, post_id: topic.first_post&.id)
      BadgeGranter.revoke(user_badge, revoked_by: moderator) if user_badge
    rescue => e
      Rails.logger.warn("NPN critique engagement: editors pick badge revoke failed: #{e.message}")
    end

    def send_pm(topic)
      return if !SiteSetting.npn_critique_editors_pick_pm_enabled
      return if topic.user.nil?

      SystemMessage.create_from_system_user(
        topic.user,
        :npn_editors_pick,
        topic_title: topic.title,
        topic_url: topic.url,
      )
    rescue => e
      Rails.logger.warn("NPN critique engagement: editors pick PM failed: #{e.message}")
    end
  end
end
