# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Month boundaries close a season: final scores freeze, badges grant, flair
  # groups sync, and a winners topic is posted. Runs from the nightly job and
  # simply catches up on any month that has not been closed yet, so downtime
  # around the 1st costs nothing.
  class SeasonCloser
    def self.close_due
      Score
        .where(finalized: false)
        .where("period_start < ?", Score.current_period_start)
        .distinct
        .order(:period_start)
        .pluck(:period_start)
        .each { |period_start| new(period_start).close }
    end

    def initialize(period_start)
      @period_start = period_start
    end

    def close
      Scorer.run(@period_start)

      rows = Score.for_period(@period_start).where(finalized: false).includes(:user).to_a
      Score.for_period(@period_start).where(finalized: false).update_all(finalized: true)

      grant_badges(rows)
      sync_flair_groups(rows)
      create_season_topic(rows)
    end

    private

    def excellent_rows(rows)
      rows.select(&:excellent?)
    end

    def grant_badges(rows)
      return if !SiteSetting.npn_critique_badges_enabled

      contributor = Badges.contributor
      supporter = Badges.supporter
      pillar = Badges.pillar

      rows.each do |row|
        next if row.user.nil?

        begin
          BadgeGranter.grant(contributor, row.user) if row.healthy? || row.excellent?
          if row.excellent?
            BadgeGranter.grant(supporter, row.user)
            BadgeGranter.grant(pillar, row.user) if pillar_earned?(row.user_id)
          end
        rescue => e
          Rails.logger.warn(
            "NPN critique engagement: badge grant failed for user #{row.user_id}: #{e.message}",
          )
        end
      end
    end

    # Excellent in N of the trailing M finalized months, including the month
    # being closed.
    def pillar_earned?(user_id)
      window_start = @period_start - (SiteSetting.npn_critique_pillar_window_months - 1).months

      Score
        .finalized
        .where(user_id: user_id, tier: :excellent)
        .where(period_start: window_start..@period_start)
        .count >= SiteSetting.npn_critique_pillar_required_months
    end

    # Supporter flair lasts for the month after earning it, so the group is
    # replaced wholesale each close. Pillar flair is permanent — members are
    # only ever added. Both groups are plugin-managed.
    def sync_flair_groups(rows)
      excellent_user_ids = excellent_rows(rows).map(&:user_id)

      if (supporter_group = flair_group(SiteSetting.npn_critique_supporter_flair_group))
        supporter_group
          .users
          .where.not(id: excellent_user_ids)
          .each { |user| supporter_group.remove(user) }
        add_members(supporter_group, excellent_user_ids)
      end

      if (pillar_group = flair_group(SiteSetting.npn_critique_pillar_flair_group))
        pillar_ids = excellent_user_ids.select { |user_id| pillar_earned?(user_id) }
        add_members(pillar_group, pillar_ids)
      end
    end

    def flair_group(setting)
      Group.find_by(id: setting.to_i) if setting.present?
    end

    def add_members(group, user_ids)
      existing = group.group_users.where(user_id: user_ids).pluck(:user_id)
      User.where(id: user_ids - existing).each { |user| group.add(user) }
    end

    def create_season_topic(rows)
      return if !SiteSetting.npn_critique_season_topic_enabled

      category_id = SiteSetting.npn_critique_category.presence&.to_i
      return if category_id.blank?

      winners =
        rows
          .select { |row| row.weighted_replies > 0 }
          .sort_by { |row| -row.weighted_replies }
          .first(SiteSetting.npn_critique_leaderboard_size)
      return if winners.empty?

      author =
        User.find_by_username(SiteSetting.npn_critique_season_topic_author) || Discourse.system_user
      month = @period_start.strftime("%B %Y")

      post =
        PostCreator.create!(
          author,
          title: I18n.t("npn_critique_engagement.season_topic.title", month: month),
          raw:
            I18n.t(
              "npn_critique_engagement.season_topic.body",
              month: month,
              winners: winners_table(winners),
            ),
          category: category_id,
          skip_validations: true,
        )

      pin_days = SiteSetting.npn_critique_season_topic_pin_days
      post.topic.update_pinned(true, false, pin_days.days.from_now.to_s) if pin_days > 0
    rescue => e
      Rails.logger.warn("NPN critique engagement: season topic failed: #{e.message}")
    end

    MEDALS = %w[🥇 🥈 🥉].freeze

    def winners_table(winners)
      header = I18n.t("npn_critique_engagement.season_topic.table_header")
      lines =
        winners.each_with_index.map do |row, index|
          rank = MEDALS[index] || "#{index + 1}."
          "| #{rank} | @#{row.user.username} | #{row.weighted_replies.round(1)} |"
        end
      ([header] + lines).join("\n")
    end
  end
end
