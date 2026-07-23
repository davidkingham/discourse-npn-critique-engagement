# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The composed homepage.
  #
  # Lanes are an allocation, not a ranking. Image Critiques out-posts every
  # other category by a wide margin, so on one merged list a discussion is
  # buried within hours no matter how that list is sorted — volume always
  # wins. Giving the conversation lane slots it keeps regardless of critique
  # volume is the only thing that fixes that.
  #
  # Order matters, top to bottom. Editors' picks come first and largest: the
  # homepage is also what a prospective member sees, and curated work should
  # set that impression. The waiting lane sits below it, capped small, under
  # a heading that says plainly what it is — so a photo there reads as
  # "someone needs help", not as "our best".
  #
  # A lane with nothing fresh renders nothing at all. A stale lane teaches
  # members to scroll past it.
  module Feed
    module_function

    def enabled?
      SiteSetting.npn_critique_engagement_enabled && SiteSetting.npn_fair_feed_enabled
    end

    # Whether this viewer should get the custom homepage.
    #
    # An empty allowed-groups list is the full rollout: every logged-in
    # member, plus anonymous if that setting is on. Once a group is set the
    # feed is a restricted beta — only members of those groups see it, and
    # anonymous visitors are excluded regardless of the anonymous setting, so
    # a production test never leaks to logged-out traffic.
    def visible_to?(user)
      return false unless enabled?

      groups = SiteSetting.npn_fair_feed_allowed_groups_map
      if groups.present?
        user.present? && user.in_any_groups?(groups)
      else
        user.present? || SiteSetting.npn_fair_feed_anonymous
      end
    end

    # Every lane the viewer should see, in display order, empty ones dropped.
    #
    # Built top to bottom through a shared `seen` set: each lane excludes every
    # topic a lane above it already showed, so a photo appears once, in its
    # most meaningful lane. That is what keeps "photographers you haven't met"
    # from echoing "waiting for a first critique", and it makes the closing
    # Latest lane a clean catch-all of everything not surfaced above.
    #
    # `layout` travels to the client because each lane needs a different one:
    # picks are cropped covers in a scrolling carousel, waiting must never
    # crop and must read in rank order, conversations carry no image at all.
    def lanes(user)
      seen = []
      [
        picks_lane(user, seen),
        lane("npn_waiting", "justified", waiting(user, seen)),
        lane("npn_new_members", "cards", new_members(user, seen)),
        lane("npn_conversation", "rows", conversation(user, seen)),
        lane("npn_unmet", "justified", unmet(user, seen)),
        lane("npn_latest", "masonry", latest(user)),
      ].compact
    end

    def lane(name, layout, list, extra = {})
      list && { name: name, layout: layout, list: list, **extra }
    end

    # Curated covers, one per genre. A row of the most-recent picks alone
    # tends to repeat a genre — three landscapes in a row says nothing about
    # the breadth of the community, which is the whole job of a shop-window
    # lane on a page that new members land on. So the carousel shows the
    # latest pick in each genre instead, newest genre first, and carries a
    # {topic_id => genre} map the client labels each card with. Cropping is
    # acceptable here and nowhere else — these are covers, not the work.
    def picks_lane(user, seen)
      chosen = latest_pick_per_genre
      return nil if chosen.blank?

      ordered_ids = chosen.map { |pick| pick[:topic_id] }
      genres = chosen.to_h { |pick| [pick[:topic_id], pick[:genre]] }

      list =
        build(user, "npn_picks", ordered_ids.size, seen) do |scope|
          scope.where(id: ordered_ids).reorder(
            Arel.sql(
              ActiveRecord::Base.sanitize_sql_array(
                ["array_position(ARRAY[?]::bigint[], topics.id)", ordered_ids],
              ),
            ),
          )
        end
      return nil if list.nil?

      lane("npn_picks", "carousel", list, genres: genres)
    end

    # The latest pick in each genre, capped, then ordered by the configured
    # genre order (npn_fair_feed_pick_genres). A pick is a topic carrying the
    # pick tag (so manually-tagged picks still count); its genre is the one the
    # moderator declared on the pick note or the staged pick, falling back to
    # the topic's own first genre tag for legacy picks that predate genre
    # recording.
    def latest_pick_per_genre
      candidates = tagged_pick_topics
      return [] if candidates.blank?

      genres = declared_pick_genres(candidates.map(&:id))
      limit = SiteSetting.npn_fair_feed_picks_limit

      seen = Set.new
      chosen = []
      candidates.each do |topic|
        genre = genres[topic.id] || first_genre_tag(topic)
        # Legacy picks with no genre at all still show, each as its own slot,
        # rather than collapsing together under a nil key.
        key = genre.presence || "topic-#{topic.id}"
        next if seen.include?(key)

        seen << key
        chosen << { topic_id: topic.id, genre: genre }
        break if chosen.size >= limit
      end

      order_by_configured_genres(chosen)
    end

    # Sort the chosen picks into the configured genre order. Genres not in the
    # config keep their relative (recency) order and sit after the configured
    # ones — the second sort key preserves that, since Ruby's sort_by is not
    # stable on its own.
    def order_by_configured_genres(chosen)
      position = pick_genre_order.each_with_index.to_h
      chosen
        .each_with_index
        .sort_by { |pick, i| [position.fetch(pick[:genre], Float::INFINITY), i] }
        .map(&:first)
    end

    # [{slug:, label:}] parsed from the setting, in display order.
    def pick_genre_config
      SiteSetting
        .npn_fair_feed_pick_genres
        .to_s
        .split("|")
        .filter_map do |entry|
          slug, label = entry.split(":", 2)
          next if slug.blank?

          { slug: slug.strip, label: (label.presence || slug).strip }
        end
    end

    def pick_genre_order
      pick_genre_config.map { |genre| genre[:slug] }
    end

    # {slug => display label} for the configured genres.
    def pick_genre_labels
      pick_genre_config.to_h { |genre| [genre[:slug], genre[:label]] }
    end

    # The label a card shows for a genre: the configured one, or a humanized
    # fallback for a genre nobody configured.
    def pick_genre_label(slug)
      pick_genre_labels[slug] || slug.to_s.tr("-", " ").capitalize
    end

    # Pick topics in the critique tree, fresh and visible, newest first. The
    # tag is the source of truth for "is a pick"; recency is the topic's own
    # age, matching how the lane ordered before.
    def tagged_pick_topics
      tag_names = SiteSetting.npn_critique_editors_pick_tag.to_s.split("|").reject(&:blank?)
      tag_ids = tag_names.present? ? Tag.where(name: tag_names).pluck(:id) : []
      cats = FairRanking.category_ids
      return [] if tag_ids.blank? || cats.blank?

      Topic
        .where(category_id: cats)
        .where(archetype: Archetype.default, deleted_at: nil, visible: true)
        .where("topics.user_id > 0")
        .where("topics.created_at >= ?", freshness_cutoff)
        .where("topics.id IN (SELECT topic_id FROM topic_tags WHERE tag_id IN (?))", tag_ids)
        .includes(:tags)
        .order("topics.created_at DESC, topics.id DESC")
        .to_a
    end

    # {topic_id => declared genre}. The pick note's genre wins over a staged
    # pick's, and the most recent note wins within a topic.
    def declared_pick_genres(topic_ids)
      return {} if topic_ids.blank?

      note_ids_by_topic =
        Post
          .where(topic_id: topic_ids, action_code: EditorsPick::ACTION_CODE, deleted_at: nil)
          .order(:created_at)
          .pluck(:topic_id, :id)
          .to_h # later notes overwrite earlier, so the newest note per topic wins
      genre_by_note =
        PostCustomField
          .where(post_id: note_ids_by_topic.values, name: EditorsPick::GENRE_FIELD)
          .pluck(:post_id, :value)
          .to_h

      genres = {}
      note_ids_by_topic.each do |topic_id, note_id|
        value = genre_by_note[note_id]
        genres[topic_id] = value if value.present?
      end

      # Staged picks fill in for anything a finalized note didn't cover.
      PendingPick
        .where(topic_id: topic_ids)
        .where.not(genre: nil)
        .pluck(:topic_id, :genre)
        .each { |topic_id, genre| genres[topic_id] ||= genre if genre.present? }

      genres
    end

    def first_genre_tag(topic)
      (topic.tags.map(&:name).sort - GenreTags.non_genre_tags).first
    end

    # The equity lane. Small on purpose: a call to action, not the page.
    def waiting(user, seen)
      build(user, "npn_waiting", SiteSetting.npn_fair_feed_waiting_limit, seen) do |scope|
        FairRanking.order_fair(FairRanking.candidates(scope: scope))
      end
    end

    # Intros that haven't collected enough replies yet. A tiny lane, and
    # almost certainly the highest-leverage one for retention.
    def new_members(user, seen)
      ids = category_tree(SiteSetting.npn_critique_new_member_category)
      return nil if ids.blank?

      build(user, "npn_new_members", SiteSetting.npn_fair_feed_new_members_limit, seen) do |scope|
        FairRanking.order_conversation(
          scope
            .where(category_id: ids)
            .where("topics.created_at >= ?", freshness_cutoff)
            .where("topics.posts_count <= ?", SiteSetting.npn_critique_new_member_min_replies),
        )
      end
    end

    # Reserved slots for everything that isn't a photo critique. Ranked
    # without the rolling score on purpose — see FairRanking#order_conversation.
    def conversation(user, seen)
      configured = SiteSetting.npn_fair_feed_conversation_categories.to_s.split("|").map(&:to_i)
      excluded =
        FairRanking.category_ids + category_tree(SiteSetting.npn_critique_new_member_category)

      build(user, "npn_conversation", SiteSetting.npn_fair_feed_conversation_limit, seen) do |scope|
        scope = scope.where(category_id: configured) if configured.present?
        scope = scope.where.not(category_id: excluded) if excluded.present?
        FairRanking.order_conversation(scope.where("topics.created_at >= ?", freshness_cutoff))
      end
    end

    NEVER_REPLIED_SQL = <<~SQL
      topics.user_id NOT IN (
        SELECT met.user_id
        FROM posts mine
        JOIN topics met ON met.id = mine.topic_id
        WHERE mine.user_id = :user_id
          AND mine.post_number > 1
          AND mine.deleted_at IS NULL
          AND mine.created_at >= :since
      )
    SQL

    # Per viewer: work by photographers this member has never replied to, and
    # — via the shared `seen` set — not already up in the waiting lane. The
    # dedup is what stops this echoing "waiting for a first critique": it
    # surfaces the strangers' work that the small waiting fold didn't reach.
    def unmet(user, seen)
      return nil if user.nil?

      build(user, "npn_unmet", SiteSetting.npn_fair_feed_unmet_limit, seen) do |scope|
        FairRanking.order_fair(
          FairRanking
            .candidates(scope: scope)
            .where.not(user_id: user.id)
            .where(NEVER_REPLIED_SQL, user_id: user.id, since: window_cutoff),
        )
      end
    end

    # The familiar feed that closes the page: the real Latest list, paginated
    # for infinite scroll and rendered as masonry — the old Latest page, in
    # other words. It is deliberately NOT deduped against the curated lanes:
    # this is the "browse everything" surface, so a photo already up in a
    # curated lane still appears here, exactly as Latest always has. Core's
    # own list_latest handles security, muting, ordering and pagination, so
    # the earlier categories-join pitfall does not apply here.
    def latest(user, page: 0)
      list =
        TopicQuery.new(
          user,
          page: [page.to_i, 0].max,
          per_page: SiteSetting.npn_fair_feed_latest_limit,
        ).list_latest
      list.topics.present? ? list : nil
    rescue StandardError => e
      Rails.logger.warn("NPN fair feed: latest lane failed: #{e.class}: #{e.message}")
      nil
    end

    # Each lane gets its own TopicQuery so per_page applies per lane. Excludes
    # everything already shown (the shared `seen` set) and adds its own results
    # to it. Returns nil rather than an empty list so the caller drops the lane.
    def build(user, name, limit, seen, &narrow)
      # Category "About" topics are excluded in list_npn_fair_lane, not via
      # TopicQuery's :no_definitions option — see the note there.
      list =
        TopicQuery.new(user, per_page: limit.to_i).list_npn_fair_lane(name, exclude: seen, &narrow)
      return nil if list.topics.blank?

      seen.concat(list.topics.map(&:id))
      list
    rescue StandardError => e
      # One broken lane must never take the whole homepage down with it.
      Rails.logger.warn("NPN fair feed: lane #{name} failed: #{e.class}: #{e.message}")
      nil
    end

    def category_tree(setting)
      category_id = setting.presence&.to_i
      return [] if category_id.nil?

      Category.where("id = :id OR parent_category_id = :id", id: category_id).pluck(:id)
    end

    def freshness_cutoff
      SiteSetting.npn_fair_feed_freshness_days.days.ago
    end

    def window_cutoff
      SiteSetting.npn_critique_window_days.days.ago
    end
  end
end
