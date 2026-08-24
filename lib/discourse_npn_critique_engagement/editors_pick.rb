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
      # Guard on the note, not the tag: a moderator who added the tag by hand
      # has a tagged-but-not-picked topic, and finalizing it is exactly how
      # they fix that. Re-tagging below is a harmless no-op when the tag is
      # already there.
      return if topic.nil? || moderator.nil? || finalized?(topic)

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

    # A finalized pick carries the moderator note — the record the full
    # process creates (note, badge, PM). The tag alone doesn't make a pick:
    # a moderator can add it by hand, and that reads as "tagged, not picked"
    # until finalized. This is what "already picked" means for the review
    # queue, matching how the dashboard counts picks by their notes.
    def finalized?(topic)
      notes(topic).exists?
    end

    def notes(topic)
      Post.where(topic_id: topic.id, action_code: ACTION_CODE, deleted_at: nil)
    end

    # Every topic a pick could be made from: real, visible image topics in
    # the critique tree, minus weekly-challenge ANNOUNCEMENTS (the marker
    # field catches ones the weekly-challenge plugin created, the title
    # prefixes catch older ones from before the marker existed). Challenge
    # ENTRIES stay pickable. The review queue, the dashboard's pick board,
    # and the since-last-pick counts all filter through here so they can
    # never disagree about what counts as an entry.
    def pickable_scope(category_ids)
      scope =
        Topic
          .where(category_id: category_ids)
          .where(archetype: Archetype.default)
          .where(deleted_at: nil, visible: true)
          .where("topics.user_id > 0")
          .where(
            "NOT EXISTS (SELECT 1 FROM topic_custom_fields tcf
             WHERE tcf.topic_id = topics.id AND tcf.name = 'npn_weekly_challenge_slug')",
          )

      SiteSetting
        .npn_critique_coverage_excluded_title_prefixes
        .to_s
        .split("|")
        .each { |prefix| scope = scope.where("topics.title NOT ILIKE ?", "#{prefix}%") }

      scope
    end

    # {genre => Time} — when each genre's slot was last filled, over all
    # time, judged by when the pick was MADE (the note, or a staged pick in
    # its undo window), not when the image was posted. Picks made before
    # genres were recorded fall back to counting for every genre their topic
    # is tagged with. This is the clock behind "entries since the last pick".
    def last_pick_at_by_genre(category_ids)
      events = []

      notes =
        Post
          .joins(:topic)
          .where(topics: { category_id: category_ids, deleted_at: nil })
          .where(action_code: ACTION_CODE, deleted_at: nil)
          .includes(topic: :tags)
          .to_a
      note_genres =
        PostCustomField
          .where(post_id: notes.map(&:id), name: GENRE_FIELD)
          .pluck(:post_id, :value)
          .to_h
      notes.each do |note|
        genres = note_genres[note.id] ? [note_genres[note.id]] : topic_genres(note.topic)
        events << [genres, note.created_at]
      end

      PendingPick
        .joins(:topic)
        .where(topics: { category_id: category_ids, deleted_at: nil })
        .includes(topic: :tags)
        .each do |pending|
          genres = pending.genre ? [pending.genre] : topic_genres(pending.topic)
          events << [genres, pending.created_at]
        end

      events.each_with_object({}) do |(genres, at), map|
        genres.each { |genre| map[genre] = [map[genre], at].compact.max }
      end
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

    def topic_genres(topic)
      topic.tags.map(&:name) - GenreTags.non_genre_tags
    end

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
