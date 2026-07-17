# frozen_string_literal: true

module Jobs
  # Fires when a staged pick's undo window closes. If the moderator undid the
  # pick in the meantime the record is gone and nothing happens — the member
  # never learns a pick was staged.
  class NpnFinalizeEditorsPick < ::Jobs::Base
    def execute(args)
      pending = DiscourseNpnCritiqueEngagement::PendingPick.find_by(id: args[:pending_pick_id])
      return if pending.nil?

      topic = Topic.find_by(id: pending.topic_id, deleted_at: nil)
      moderator = User.find_by(id: pending.user_id)
      if topic && moderator
        DiscourseNpnCritiqueEngagement::EditorsPick.finalize!(
          topic: topic,
          moderator: moderator,
          genre: pending.genre,
          reason: pending.reason,
        )
      end
      pending.destroy!
    end
  end
end
