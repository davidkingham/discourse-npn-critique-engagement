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

    # Every lane the viewer should see, in display order, empty ones dropped.
    # `layout` travels to the client because each lane needs a different one:
    # picks are cropped covers, waiting must never crop and must read in rank
    # order, conversations carry no image at all.
    def lanes(user)
      [
        lane("npn_picks", "hero", picks(user)),
        lane("npn_waiting", "justified", waiting(user)),
        lane("npn_new_members", "cards", new_members(user)),
        lane("npn_conversation", "rows", conversation(user)),
        lane("npn_unmet", "justified", unmet(user)),
      ].compact
    end

    def lane(name, layout, list)
      list && { name: name, layout: layout, list: list }
    end

    # Curated covers: recent editors' picks. Cropping is acceptable here and
    # nowhere else — these are covers, not the work itself.
    def picks(user)
      tag_names = SiteSetting.npn_critique_editors_pick_tag.to_s.split("|").reject(&:blank?)
      tag_ids = tag_names.present? ? Tag.where(name: tag_names).pluck(:id) : []
      return nil if tag_ids.blank?

      build(user, "npn_picks", SiteSetting.npn_fair_feed_picks_limit) do |scope|
        scope
          .where("topics.id IN (SELECT topic_id FROM topic_tags WHERE tag_id IN (?))", tag_ids)
          .where("topics.created_at >= ?", freshness_cutoff)
          .reorder("topics.created_at DESC, topics.id DESC")
      end
    end

    # The equity lane. Small on purpose: a call to action, not the page.
    def waiting(user)
      build(user, "npn_waiting", SiteSetting.npn_fair_feed_waiting_limit) do |scope|
        FairRanking.order_fair(FairRanking.candidates(scope: scope))
      end
    end

    # Intros that haven't collected enough replies yet. A tiny lane, and
    # almost certainly the highest-leverage one for retention.
    def new_members(user)
      ids = category_tree(SiteSetting.npn_critique_new_member_category)
      return nil if ids.blank?

      build(user, "npn_new_members", SiteSetting.npn_fair_feed_new_members_limit) do |scope|
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
    def conversation(user)
      configured = SiteSetting.npn_fair_feed_conversation_categories.to_s.split("|").map(&:to_i)
      excluded =
        FairRanking.category_ids + category_tree(SiteSetting.npn_critique_new_member_category)

      build(user, "npn_conversation", SiteSetting.npn_fair_feed_conversation_limit) do |scope|
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

    # Per viewer: work by photographers this member has never replied to.
    # Deliberately its own small lane rather than a personalization of the
    # main ranking, so the shared feed stays shared, cacheable and
    # explainable when somebody asks why they see what they see.
    def unmet(user)
      return nil if user.nil?

      build(user, "npn_unmet", SiteSetting.npn_fair_feed_unmet_limit) do |scope|
        FairRanking.order_fair(
          FairRanking
            .candidates(scope: scope)
            .where.not(user_id: user.id)
            .where(NEVER_REPLIED_SQL, user_id: user.id, since: window_cutoff),
        )
      end
    end

    # Each lane gets its own TopicQuery so per_page applies per lane. Returns
    # nil rather than an empty list so the caller can drop the lane outright.
    def build(user, name, limit, &narrow)
      # no_definitions keeps the auto-generated "About the … category" topics
      # out. They carry no image and nobody is waiting for a critique on one.
      list =
        TopicQuery.new(
          user,
          per_page: limit.to_i,
          no_definitions: !SiteSetting.show_category_definitions_in_topic_lists,
        ).list_npn_fair_lane(name, &narrow)
      list.topics.present? ? list : nil
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
