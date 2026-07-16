# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # The critique engagement formula: turns a member's monthly aggregates
  # (quality-weighted critique output vs. photos posted) into a score and a
  # tier. Ported verbatim from the tuned Data Explorer prototype; the curve
  # constants below are the prototype's, while every behavioral knob (length
  # tiers, like bonus, follow-up credit, tier boundaries, grace window) is a
  # site setting.
  module Formula
    # Reply-quality log multiplier for pure repliers and healthy-ratio members.
    BASE_MULTIPLIER = 100.0
    # Reply credit earned while below the healthy ratio.
    PARTIAL_MULTIPLIER = 70.0
    # Penalty per ratio-unit shortfall between 1:1 and the target ratio.
    MILD_PENALTY_SLOPE = 40.0
    # Topic-volume penalty log multiplier (members posting without replying).
    TOPIC_PENALTY_MULTIPLIER = 100.0
    RATIO_BONUS_MULTIPLIER = 15.0
    RATIO_BONUS_CAP = 50.0
    ACTIVITY_BONUS_MULTIPLIER = 12.0
    ACTIVITY_BONUS_CAP = 40.0
    # Grace-protected members never score below this floor.
    GRACE_FLOOR = 20.0
    GRACE_MULTIPLIER = 90.0

    # How far the simulation in .critiques_to_reach will look ahead before
    # giving up. Far beyond anything the private panel would ever suggest.
    SIMULATION_LIMIT = 50

    # grace: the member is inside the new-member window and not topic-dumping,
    # so they score on the protected curve (never penalized while finding
    # their feet).
    def self.score(weighted_replies:, created_topics:, topics_replied:, grace: false)
      reply_log = Math.log(weighted_replies + 1)

      value =
        if grace
          [GRACE_FLOOR, GRACE_MULTIPLIER * reply_log].max
        elsif created_topics == 0
          # Pure repliers: full reply credit, no topic bonus, never a penalty.
          BASE_MULTIPLIER * reply_log
        elsif topics_replied == 0
          # Topic-only members: penalty scales with volume.
          -TOPIC_PENALTY_MULTIPLIER * Math.log(created_topics + 1)
        else
          ratio = topics_replied.to_f / created_topics
          if ratio < 1
            # Reply effort earns partial credit scaled by ratio; the penalty
            # shrinks smoothly to zero as the ratio approaches 1:1.
            # Continuous with the topic-only branch at ratio 0.
            (PARTIAL_MULTIPLIER * reply_log * ratio) -
              (TOPIC_PENALTY_MULTIPLIER * (1 - ratio) * Math.log(created_topics + 1))
          elsif ratio < SiteSetting.npn_critique_target_ratio
            # Mild penalty between 1:1 and the healthy ratio.
            (PARTIAL_MULTIPLIER * reply_log) -
              (MILD_PENALTY_SLOPE * (SiteSetting.npn_critique_target_ratio - ratio))
          else
            # Healthy ratio: reply quality dominates, with capped bonuses for
            # generosity and for posting photos too.
            (BASE_MULTIPLIER * reply_log) +
              [RATIO_BONUS_MULTIPLIER * Math.log(ratio + 1), RATIO_BONUS_CAP].min +
              [ACTIVITY_BONUS_MULTIPLIER * Math.log(created_topics + 1), ACTIVITY_BONUS_CAP].min
          end
        end

      value.round
    end

    def self.ratio(created_topics:, topics_replied:)
      topics_replied.to_f / [created_topics, 1].max
    end

    # Tier follows the prototype exactly: members inside the grace window are
    # always labeled new_member (judge gently; welcome them) — topic-dumping
    # only removes the score protection, never the label.
    def self.tier_for(user:, score:, created_topics:)
      return :new_member if in_grace_period?(user)

      if score >= SiteSetting.npn_critique_excellent_score
        :excellent
      elsif score >= SiteSetting.npn_critique_healthy_score
        :healthy
      elsif score >= SiteSetting.npn_critique_watch_floor_score
        :watch
      elsif created_topics >= SiteSetting.npn_critique_outreach_min_topics
        :priority_outreach
      else
        :low_activity
      end
    end

    # Whether the member scores on the protected curve: inside the grace
    # window and not immediately topic-dumping.
    def self.grace_protected?(user:, created_topics:, topics_replied:)
      in_grace_period?(user) &&
        !topic_dump?(created_topics: created_topics, topics_replied: topics_replied)
    end

    # Account age at scoring time, exactly like the prototype.
    def self.in_grace_period?(user)
      user.created_at > Time.zone.now - SiteSetting.npn_critique_grace_period_days.days
    end

    def self.topic_dump?(created_topics:, topics_replied:)
      topics_replied == 0 && created_topics >= SiteSetting.npn_critique_grace_topic_dump_threshold
    end

    # How many additional substantive critiques (each opening one new thread
    # of reciprocation) would lift this member to target_score. Powers the
    # private panel's "2 more critiques this month reaches Healthy" line.
    def self.critiques_to_reach(
      target_score,
      weighted_replies:,
      created_topics:,
      topics_replied:,
      grace: false
    )
      (1..SIMULATION_LIMIT).each do |additional|
        simulated =
          score(
            weighted_replies: weighted_replies + additional,
            created_topics: created_topics,
            topics_replied: topics_replied + additional,
            grace: grace,
          )
        return additional if simulated >= target_score
      end
      nil
    end
  end
end
