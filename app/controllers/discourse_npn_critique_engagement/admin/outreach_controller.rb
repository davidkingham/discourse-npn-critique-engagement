# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  module Admin
    # The outreach queue: priority-outreach members with a "last contacted"
    # note, so two moderators don't double-nudge the same person.
    class OutreachController < ::Admin::StaffController
      requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME

      NOTES_LIMIT = 20

      WELCOME_LIMIT = 20

      # GET /admin/plugins/critique-engagement/outreach
      # Two queues, opposite valences: members to nudge (posting without
      # giving) and new members to welcome (already giving — a personal hello
      # goes a long way).
      def index
        excluded_ids = OutreachExclusion.active_user_ids

        rows =
          Score
            .where(tier: :priority_outreach)
            .where.not(user_id: excluded_ids)
            .includes(:user)
            .order(score: :asc)
            .reject { |row| row.user.nil? }

        welcome_rows =
          Score
            .where(tier: :new_member)
            .where("weighted_replies > 0")
            .where.not(user_id: excluded_ids)
            .includes(:user)
            .order(weighted_replies: :desc)
            .limit(WELCOME_LIMIT)
            .reject { |row| row.user.nil? }

        # Set aside, not gone: the queue shows its own exclusions so the
        # decision stays visible and reversible instead of becoming a hole
        # nobody can audit.
        excluded_rows =
          Score
            .where(user_id: excluded_ids)
            .includes(:user)
            .order(score: :asc)
            .reject { |row| row.user.nil? }

        all_user_ids = (rows + welcome_rows + excluded_rows).map(&:user_id)
        outreach_logs = OutreachLog.latest_for(all_user_ids)
        # Which genres each member posts to, so the right genre moderator
        # makes the contact.
        top_tags = GenreTags.top_for_users(all_user_ids)
        claims = OutreachClaim.active_for(all_user_ids)
        exclusions = OutreachExclusion.active_for(all_user_ids)

        render json: {
                 rows:
                   serialize_data(
                     rows,
                     ReportRowSerializer,
                     outreach_logs: outreach_logs,
                     top_tags: top_tags,
                     claims: claims,
                   ),
                 welcome_rows:
                   serialize_data(
                     welcome_rows,
                     ReportRowSerializer,
                     outreach_logs: outreach_logs,
                     top_tags: top_tags,
                     claims: claims,
                   ),
                 excluded_rows:
                   serialize_data(
                     excluded_rows,
                     ReportRowSerializer,
                     outreach_logs: outreach_logs,
                     top_tags: top_tags,
                     exclusions: exclusions,
                   ),
               }
      end

      # GET /admin/plugins/critique-engagement/outreach/:user_id/notes
      def notes
        user = User.find_by(id: params[:user_id])
        raise Discourse::NotFound if user.nil?

        logs =
          OutreachLog
            .where(user_id: user.id)
            .includes(:staff_user)
            .order(created_at: :desc)
            .limit(NOTES_LIMIT)

        render json: { notes: serialize_data(logs, OutreachLogSerializer) }
      end

      # POST /admin/plugins/critique-engagement/outreach/notes
      def create
        user = User.find_by(id: params.require(:user_id))
        raise Discourse::NotFound if user.nil?

        log = OutreachLog.create!(user: user, staff_user: current_user, note: params.require(:note))
        # The contact happened — whoever claimed it is done.
        OutreachClaim.where(user_id: user.id).destroy_all

        render json: OutreachLogSerializer.new(log, root: false).as_json, status: :created
      end

      # POST /admin/plugins/critique-engagement/outreach/claim
      # "I'll reach out" — visible to every other moderator so nobody writes
      # the same member twice.
      def claim
        user = User.find_by(id: params.require(:user_id))
        raise Discourse::NotFound if user.nil?

        if OutreachExclusion.active.exists?(user_id: user.id)
          return(
            render_json_error(
              I18n.t("npn_critique_engagement.outreach.excluded_member"),
              status: 409,
            )
          )
        end

        existing = OutreachClaim.find_by(user_id: user.id)
        if existing&.active? && existing.staff_user_id != current_user.id
          return(
            render_json_error(
              I18n.t(
                "npn_critique_engagement.outreach.already_claimed",
                username: existing.staff_user&.username,
              ),
              status: 409,
            )
          )
        end

        claim = existing || OutreachClaim.new(user_id: user.id)
        claim.staff_user = current_user
        claim.created_at = Time.zone.now
        claim.save!

        render json: claim_payload(claim), status: :created
      end

      # DELETE /admin/plugins/critique-engagement/outreach/claim
      def unclaim
        claim =
          OutreachClaim.find_by(user_id: params.require(:user_id), staff_user_id: current_user.id)
        claim&.destroy!

        head :no_content
      end

      # POST /admin/plugins/critique-engagement/outreach/exclusion
      # "Leave them be" — take a member off the outreach queues without
      # touching their score. Optionally for a set number of days; by default
      # indefinitely.
      def exclude
        user = User.find_by(id: params.require(:user_id))
        raise Discourse::NotFound if user.nil?

        reason = params.require(:reason).to_s.strip
        raise Discourse::InvalidParameters.new(:reason) if reason.blank?
        if reason.length > OutreachExclusion::REASON_MAX_LENGTH
          raise Discourse::InvalidParameters.new(:reason)
        end

        days = params[:days].presence&.to_i
        raise Discourse::InvalidParameters.new(:days) if days && days < 1

        exclusion = OutreachExclusion.find_or_initialize_by(user_id: user.id)
        exclusion.staff_user = current_user
        exclusion.reason = reason
        exclusion.expires_at = days&.days&.from_now
        exclusion.save!

        # The decision supersedes any outstanding "I'll reach out".
        OutreachClaim.where(user_id: user.id).destroy_all

        render json: exclusion_payload(exclusion), status: :created
      end

      # DELETE /admin/plugins/critique-engagement/outreach/exclusion
      def unexclude
        OutreachExclusion.where(user_id: params.require(:user_id)).destroy_all

        head :no_content
      end

      private

      def exclusion_payload(exclusion)
        {
          username: exclusion.staff_user&.username,
          reason: exclusion.reason,
          created_at: exclusion.created_at,
          expires_at: exclusion.expires_at,
        }
      end

      def claim_payload(claim)
        {
          username: claim.staff_user&.username,
          claimed_at: claim.created_at,
          mine: claim.staff_user_id == current_user.id,
        }
      end
    end
  end
end
