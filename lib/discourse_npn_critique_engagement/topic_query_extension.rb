# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Prepended into TopicQuery (the pattern discourse-templates and the NPN
  # weekly-challenge plugin use) so the feed's lanes build on the protected
  # #default_results — the relation that already enforces secured categories,
  # unlisted/deleted visibility and muting. Every lane only ever narrows it,
  # so a lane can never surface a topic the viewer isn't allowed to see.
  module TopicQueryExtension
    # One lane. `narrow` receives the secured relation and returns a narrowed,
    # ordered one; `name` is the list's filter name, which the client uses to
    # tell lanes apart.
    def list_npn_fair_lane(name, &narrow)
      create_list(name, {}, narrow.call(default_results))
    end
  end
end
