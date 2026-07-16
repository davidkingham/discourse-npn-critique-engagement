# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  module Admin
    # The outreach queue: priority-outreach members with a "last contacted"
    # note, so two moderators don't double-nudge the same person.
    class OutreachController < ::Admin::StaffController
      requires_plugin DiscourseNpnCritiqueEngagement::PLUGIN_NAME

      NOTES_LIMIT = 20

      # GET /admin/plugins/critique-engagement/outreach
      def index
        rows =
          Score
            .where(tier: :priority_outreach)
            .includes(:user)
            .order(score: :asc)
            .reject { |row| row.user.nil? }

        render json: {
                 rows:
                   serialize_data(
                     rows,
                     ReportRowSerializer,
                     outreach_logs: OutreachLog.latest_for(rows.map(&:user_id)),
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

        render json: OutreachLogSerializer.new(log, root: false).as_json, status: :created
      end
    end
  end
end
