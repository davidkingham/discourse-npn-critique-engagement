# frozen_string_literal: true

module DiscourseNpnCritiqueEngagement
  # Prepended into TopicQuery (the pattern discourse-templates and the NPN
  # weekly-challenge plugin use) so the feed's lanes build on the protected
  # #default_results — the relation that already enforces secured categories,
  # unlisted/deleted visibility and muting. Every lane only ever narrows it,
  # so a lane can never surface a topic the viewer isn't allowed to see.
  module TopicQueryExtension
    # A category's "About" topic is its definition topic — it carries no image
    # and nobody is waiting to critique one, so it never belongs in a lane.
    #
    # Excluded with a self-contained subquery rather than TopicQuery's
    # :no_definitions option. That option adds `COALESCE(categories.topic_id,
    # 0) <> topics.id`, which references the categories table without joining
    # it; core's own list path happens to carry that join, but this custom
    # relation does not, so on a site with category definitions hidden the
    # option raises "missing FROM-clause entry for table categories" and takes
    # every lane down with it. The subquery needs no join and so is safe
    # wherever it runs.
    NOT_CATEGORY_DEFINITION =
      "topics.id NOT IN (SELECT c.topic_id FROM categories c WHERE c.topic_id IS NOT NULL)"

    # One lane. `narrow` receives the secured relation and returns a narrowed,
    # ordered one; `name` is the list's filter name, which the client uses to
    # tell lanes apart.
    def list_npn_fair_lane(name, &narrow)
      results = narrow.call(default_results).where(NOT_CATEGORY_DEFINITION)
      create_list(name, {}, results)
    end
  end
end
