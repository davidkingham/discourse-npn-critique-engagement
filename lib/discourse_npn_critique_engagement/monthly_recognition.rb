# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Monthly bookkeeping on the 1st: records every member's rolling standing
  # as that month's snapshot, grants badges, syncs the optional flair groups,
  # and posts the highlights topic. Nothing resets — the rolling score is
  # untouched. Runs from the nightly job; a missed 1st is simply caught up
  # the next night.
  class MonthlyRecognition
    def self.record_due
      month = Date.current.prev_month.beginning_of_month
      return if MonthlySnapshot.for_month(month).exists?

      first_run = Scorer.first_run_at
      return if first_run.nil?
      # Don't fabricate history: skip months that ended before the plugin
      # started watching (fresh installs mid-month).
      return if first_run > month.end_of_month.end_of_day

      new(month).record
    end

    def initialize(month)
      @month = month
    end

    RISING_CRITIC_KEY = "rising_critic"

    def record
      snapshots = record_snapshots
      grant_badges(snapshots)
      rising_winner = award_rising_critic(snapshots)
      sync_flair_groups(snapshots)
      create_highlights_topic(snapshots, rising_winner)
      Recognition.rebuild!
    end

    private

    def record_snapshots
      Score
        .includes(:user)
        .reject { |row| row.user.nil? }
        .map do |row|
          MonthlySnapshot.create!(
            user_id: row.user_id,
            snapshot_month: @month,
            score: row.score,
            tier: row.tier,
            created_topics: row.created_topics,
            topics_replied: row.topics_replied,
            weighted_replies: row.weighted_replies,
            awards_received: row.awards_received,
            ratio: row.ratio,
            computed_at: row.computed_at,
          )
        end
    end

    def excellent_snapshots(snapshots)
      snapshots.select(&:excellent?)
    end

    def grant_badges(snapshots)
      return if !SiteSetting.npn_critique_badges_enabled

      contributor = Badges.contributor
      guide = Badges.supporter
      steward = Badges.pillar

      snapshots.each do |snapshot|
        user = snapshot.user
        next if user.nil?

        begin
          BadgeGranter.grant(contributor, user) if snapshot.healthy? || snapshot.excellent?
          if snapshot.excellent?
            BadgeGranter.grant(guide, user)
            BadgeGranter.grant(steward, user) if steward_earned?(snapshot.user_id)
          end
        rescue => e
          Rails.logger.warn(
            "NPN critique engagement: badge grant failed for user #{snapshot.user_id}: #{e.message}",
          )
        end
      end
    end

    # The month's most generous new critic: youngest-account members only,
    # a minimum bar so quiet months award nobody, and one win per member ever
    # — it is a welcome spotlight, not a ladder. The winner is remembered so
    # their chip shows for the following month.
    def award_rising_critic(snapshots)
      return if !SiteSetting.npn_critique_rising_enabled

      badge = Badges.rising
      previous_winner_ids = UserBadge.where(badge_id: badge.id).pluck(:user_id)
      newness_cutoff =
        @month.end_of_month.end_of_day - SiteSetting.npn_critique_rising_new_user_days.days

      winner =
        snapshots
          .select do |snapshot|
            snapshot.weighted_replies >= SiteSetting.npn_critique_rising_min_weighted
          end
          .reject { |snapshot| previous_winner_ids.include?(snapshot.user_id) }
          .select { |snapshot| snapshot.user && snapshot.user.created_at > newness_cutoff }
          .max_by { |snapshot| [snapshot.weighted_replies, snapshot.score] }
      return if winner.nil?

      BadgeGranter.grant(badge, winner.user)
      SystemMessage.create_from_system_user(
        winner.user,
        :npn_rising_critic,
        month: @month.strftime("%B %Y"),
        weighted: winner.weighted_replies.round(1).to_s,
        badge_name: badge.name,
      )
      PluginStore.set(
        PLUGIN_NAME,
        RISING_CRITIC_KEY,
        { "user_id" => winner.user_id, "month" => @month.to_s },
      )
      winner
    rescue => e
      Rails.logger.warn("NPN critique engagement: rising critic award failed: #{e.message}")
      nil
    end

    # Excellent in N of the trailing M snapshot months, including the month
    # being recorded.
    def steward_earned?(user_id)
      window_start = @month - (SiteSetting.npn_critique_pillar_window_months - 1).months

      MonthlySnapshot
        .where(user_id: user_id, tier: :excellent)
        .where(snapshot_month: window_start..@month)
        .count >= SiteSetting.npn_critique_pillar_required_months
    end

    # The flair groups are optional rosters (avatar flair is used for paying
    # members on NPN, so recognition renders as chips instead). Guide group
    # membership is replaced wholesale each month; steward membership is
    # permanent — members are only ever added. Both groups are
    # plugin-managed.
    def sync_flair_groups(snapshots)
      excellent_user_ids = excellent_snapshots(snapshots).map(&:user_id)

      if (guide_group = flair_group(SiteSetting.npn_critique_supporter_flair_group))
        guide_group.users.where.not(id: excellent_user_ids).each { |user| guide_group.remove(user) }
        add_members(guide_group, excellent_user_ids)
      end

      if (steward_group = flair_group(SiteSetting.npn_critique_pillar_flair_group))
        steward_ids = excellent_user_ids.select { |user_id| steward_earned?(user_id) }
        add_members(steward_group, steward_ids)
      end
    end

    def flair_group(setting)
      Group.find_by(id: setting.to_i) if setting.present?
    end

    def add_members(group, user_ids)
      existing = group.group_users.where(user_id: user_ids).pluck(:user_id)
      User.where(id: user_ids - existing).each { |user| group.add(user) }
    end

    def create_highlights_topic(snapshots, rising_winner)
      return if !SiteSetting.npn_critique_season_topic_enabled

      category_id = SiteSetting.npn_critique_category.presence&.to_i
      return if category_id.blank?

      winners =
        snapshots
          .select { |snapshot| snapshot.weighted_replies > 0 }
          .sort_by { |snapshot| -snapshot.weighted_replies }
          .first(SiteSetting.npn_critique_leaderboard_size)
      return if winners.empty?

      author =
        User.find_by_username(SiteSetting.npn_critique_season_topic_author) || Discourse.system_user
      month = @month.strftime("%B %Y")

      raw =
        I18n.t(
          "npn_critique_engagement.highlights_topic.body",
          month: month,
          winners: winners_table(winners),
        )
      raw += awarded_critiques_section(month)
      if rising_winner
        raw +=
          "\n\n" +
            I18n.t(
              "npn_critique_engagement.highlights_topic.rising_line",
              username: rising_winner.user.username,
              weighted: rising_winner.weighted_replies.round(1),
            )
      end

      post =
        PostCreator.create!(
          author,
          title: I18n.t("npn_critique_engagement.highlights_topic.title", month: month),
          raw: raw,
          category: category_id,
          skip_validations: true,
        )

      pin_days = SiteSetting.npn_critique_season_topic_pin_days
      post.topic.update_pinned(true, false, pin_days.days.from_now.to_s) if pin_days > 0
    rescue => e
      Rails.logger.warn("NPN critique engagement: highlights topic failed: #{e.message}")
    end

    # The month's most-awarded critiques, linked so everyone can see what a
    # great critique looks like.
    def awarded_critiques_section(month)
      entries =
        AwardedCritiques.top(
          limit: SiteSetting.npn_critique_top_critiques_count,
          period_start: @month,
          period_end: @month.next_month,
        )
      return "" if entries.empty?

      lines =
        entries.each_with_index.map do |entry, index|
          I18n.t(
            "npn_critique_engagement.highlights_topic.awarded_line",
            rank: index + 1,
            username: entry[:post].user.username,
            topic_title: entry[:post].topic.title,
            url: entry[:post].url,
            count: entry[:award_count],
          )
        end

      "\n\n## " +
        I18n.t("npn_critique_engagement.highlights_topic.awarded_section_title", month: month) +
        "\n\n" + lines.join("\n")
    end

    MEDALS = %w[🥇 🥈 🥉].freeze

    def winners_table(winners)
      header = I18n.t("npn_critique_engagement.highlights_topic.table_header")
      lines =
        winners.each_with_index.map do |snapshot, index|
          rank = MEDALS[index] || "#{index + 1}."
          "| #{rank} | @#{snapshot.user.username} | #{snapshot.weighted_replies.round(1)} |"
        end
      ([header] + lines).join("\n")
    end
  end
end
