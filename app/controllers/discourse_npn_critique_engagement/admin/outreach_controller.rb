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
        rows =
          Score
            .where(tier: :priority_outreach)
            .includes(:user)
            .order(score: :asc)
            .reject { |row| row.user.nil? }

        welcome_rows =
          Score
            .where(tier: :new_member)
            .where("weighted_replies > 0")
            .includes(:user)
            .order(weighted_replies: :desc)
            .limit(WELCOME_LIMIT)
            .reject { |row| row.user.nil? }

        all_user_ids = (rows + welcome_rows).map(&:user_id)
        outreach_logs = OutreachLog.latest_for(all_user_ids)
        # Which genres each member posts to, so the right genre moderator
        # makes the contact.
        top_tags = GenreTags.top_for_users(all_user_ids)
        claims = OutreachClaim.active_for(all_user_ids)

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

      private

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
