# frozen_string_literal: true

class AddRemindedAtToNpnCritiqueOutreachClaims < ActiveRecord::Migration[8.0]
  def change
    add_column :npn_critique_outreach_claims, :reminded_at, :datetime
  end
end
