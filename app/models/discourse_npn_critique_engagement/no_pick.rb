# frozen_string_literal: true

# Referenced in the class body below, and this file can be autoloaded before
# after_initialize has required the libs.
require_relative "../../../lib/discourse_npn_critique_engagement/pick_week"

module DiscourseNpnCritiqueEngagement
  # A deliberate "no pick this week" for a genre — a moderator judged the
  # week's images and found nothing strong enough. It marks the slot as
  # handled on the dashboard board, distinct from a slot nobody got to.
  # Keyed on when it was declared, like picks, so it resets at Pacific
  # midnight on Sunday.
  class NoPick < ActiveRecord::Base
    self.table_name = "npn_critique_no_picks"

    belongs_to :user

    validates :genre, presence: true

    scope :since, ->(time) { where(created_at: time..) }

    def self.current_week
      since(PickWeek.cutoff(PickWeek.current_start))
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
