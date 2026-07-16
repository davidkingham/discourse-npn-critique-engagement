# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  class SnapshotRowSerializer < ImpactRowSerializer
    attributes :month

    def month
      object.snapshot_month
    end
  end
end
