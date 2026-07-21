# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # A deliberate "no pick this week" for a genre — a moderator judged the
  # week's images and found nothing strong enough. It marks the slot as
  # handled on the dashboard board, distinct from a slot nobody got to.
  # Keyed on when it was declared, like picks, so it resets every Sunday.
  class NoPick < ActiveRecord::Base
    self.table_name = "npn_critique_no_picks"

    belongs_to :user

    validates :genre, presence: true

    scope :since, ->(time) { where(created_at: time..) }

    def self.current_week
      since(Date.current.beginning_of_week(:sunday).beginning_of_day)
    end
  end
end

# == Schema Information
#
# Table name: npn_critique_no_picks
#
#  id         :bigint           not null, primary key
#  genre      :string           not null
#  user_id    :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_npn_critique_no_picks_on_genre_and_created_at  (genre,created_at)
#
