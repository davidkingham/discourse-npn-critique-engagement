# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  class OutreachLogSerializer < ApplicationSerializer
    attributes :id, :user_id, :note, :created_at, :staff_username

    def staff_username
      object.staff_user&.username
    end
  end
end
