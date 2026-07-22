# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # A weekly question posted into the discussion category.
  #
  # The fair feed keeps discussions in front of people, but visibility can't
  # fill an empty room — discussions die from nobody starting them as much as
  # from nobody seeing them. This posts one question a week from a bank the
  # moderators fill, so the room always has something to answer without anyone
  # remembering to start the thread.
  #
  # Built the same way as the weekly-challenge publisher, and for the same
  # reasons: Jobs::Scheduled can't express "Mondays", so the job polls often
  # and this returns early on all but one run a week. A topic custom field is
  # the sole record of which week has been posted, so a double run can't
  # double-post, and it never raises — a missing category or a deleted author
  # degrades to "nothing posted" plus a warning, leaving the job green.
  module DiscussionPrompt
    WEEK_FIELD = "npn_discussion_prompt_week"

    # Weeks are counted from a fixed Monday so the rotation advances by one
    # every week and never resets at a year boundary (unlike cweek).
    ROTATION_EPOCH = Date.new(2024, 1, 1)

    module_function

    def enabled?
      SiteSetting.npn_critique_engagement_enabled && SiteSetting.npn_discussion_prompt_enabled &&
        SiteSetting.npn_discussion_prompt_category.present? && questions.present?
    end

    # Post this week's question if it hasn't gone up yet. Returns the Topic on
    # success, nil otherwise.
    def post_due(today: Date.current)
      return nil unless enabled?

      week = week_key(today)
      return nil if posted_for_week?(week)

      DistributedMutex.synchronize("npn_discussion_prompt_#{week}") do
        # A concurrent run may have just posted; re-check inside the lock.
        next nil if posted_for_week?(week)
        post(week, today)
      end
    rescue StandardError => e
      log_failure("unexpected error", e)
      nil
    end

    def post(week, today)
      category_id = SiteSetting.npn_discussion_prompt_category.to_i
      return nil if category_id.zero?

      question = question_for(today)
      return nil if question.blank?

      post =
        PostCreator.create!(
          author,
          title: unique_title(question, today),
          raw: body(question),
          category: category_id,
          skip_validations: true,
          topic_opts: {
            custom_fields: {
              WEEK_FIELD => week,
            },
          },
        )

      rotate_pin(post.topic) if SiteSetting.npn_discussion_prompt_pin
      post.topic
    rescue StandardError => e
      log_failure("could not post the weekly question", e)
      nil
    end

    # The week's question, chosen by rotation so the bank is exhausted before
    # any question repeats.
    def question_for(today)
      bank = questions
      return nil if bank.blank?

      bank[weeks_since_epoch(today) % bank.size]
    end

    def questions
      SiteSetting.npn_discussion_prompt_questions.to_s.split("|").map(&:strip).reject(&:blank?)
    end

    # Monday-anchored (or whatever weekday the setting names) start of `today`'s
    # week, as the record of "which week". One post per such week.
    def week_key(today)
      today.beginning_of_week(anchor_day).iso8601
    end

    def anchor_day
      SiteSetting.npn_discussion_prompt_day.to_s.downcase.to_sym
    end

    def weeks_since_epoch(today)
      (today.beginning_of_week(anchor_day) - ROTATION_EPOCH.beginning_of_week(anchor_day)).to_i / 7
    end

    def posted_for_week?(week)
      TopicCustomField.where(name: WEEK_FIELD, value: week).exists?
    end

    # The question is the title. Titles must be unique and the bank cycles, so
    # a repeat is disambiguated with its week — mirroring the challenge
    # publisher. skip_validations does not waive the uniqueness check.
    def unique_title(question, today)
      return question unless title_taken?(question)

      "#{question} (#{today.beginning_of_week(anchor_day).strftime("%b %-d")})"
    end

    def title_taken?(title)
      Topic.listable_topics.where("lower(topics.title) = ?", title.downcase).exists?
    end

    def body(question)
      template = SiteSetting.npn_discussion_prompt_body.to_s.strip
      template = default_body if template.blank?

      begin
        template % { question: question }
      rescue KeyError, ArgumentError => e
        log_failure("the body template is invalid", e)
        default_body % { question: question }
      end
    end

    def default_body
      I18n.t("npn_critique_engagement.discussion_prompt.default_body")
    end

    # Pin this week's question and unpin any earlier one this job pinned. A
    # question pinned by hand before the automation has to be unpinned once, by
    # hand — only topics carrying the week field can be found here.
    def rotate_pin(topic)
      Topic
        .joins(:_custom_fields)
        .where(topic_custom_fields: { name: WEEK_FIELD })
        .where.not(id: topic.id)
        .where.not(pinned_at: nil)
        .find_each { |old| old.update_pinned(false) }

      # Category pin, not global — matching the weekly challenge.
      topic.update_pinned(true, false)
    end

    def author
      Discourse.system_user
    end

    def log_failure(message, error)
      Rails.logger.warn("NPN discussion prompt: #{message}: #{error.class}: #{error.message}")
    end
  end
end
