# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  class OutreachLog < ActiveRecord::Base
    self.table_name = "npn_critique_outreach_logs"

    belongs_to :user
    belongs_to :staff_user, class_name: "User"

    validates :note, presence: true, length: { maximum: 5000 }

    def self.latest_for(user_ids)
      where(user_id: user_ids)
        .order(:user_id, created_at: :desc)
        .select("DISTINCT ON (user_id) npn_critique_outreach_logs.*")
        .index_by(&:user_id)
    end
  end
end

# == Schema Information
#
# Table name: npn_critique_outreach_logs
#
#  id            :bigint           not null, primary key
#  user_id       :integer          not null
#  staff_user_id :integer          not null
#  note          :text             not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_npn_critique_outreach_logs_on_user_id_and_created_at  (user_id,created_at)
#
