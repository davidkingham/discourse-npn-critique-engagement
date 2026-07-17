import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import NpnEditorsPickModal from "../components/npn-editors-pick-modal";

// The public "selected this as an Editor's Pick" note posted on a topic when
// a moderator makes a pick, and the staff shortcut for making the pick right
// from the image post instead of the pick queue.
export default {
  name: "npn-critique-post-actions",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.npn_critique_engagement_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.addPostSmallActionIcon("npn_editors_pick", "star");

      const currentUser = api.getCurrentUser();
      const categoryId = parseInt(siteSettings.npn_critique_category, 10);
      if (!currentUser?.staff || !categoryId) {
        return;
      }

      const site = container.lookup("service:site");
      const pickTag =
        (siteSettings.npn_critique_editors_pick_tag || "").split("|")[0] ||
        "editors-pick";
      const excludedTags = (siteSettings.npn_critique_pick_excluded_tags || "")
        .split("|")
        .filter(Boolean);

      const inCritiqueCategory = (topic) => {
        if (topic.category_id === categoryId) {
          return true;
        }
        const category = site.categories.find(
          (c) => c.id === topic.category_id
        );
        return category?.parent_category_id === categoryId;
      };

      api.addPostAdminMenuButton((post) => {
        const topic = post.topic;
        if (
          !topic ||
          post.post_number !== 1 ||
          !inCritiqueCategory(topic) ||
          (topic.tags || []).includes(pickTag)
        ) {
          return;
        }

        return {
          icon: "star",
          label: "npn_critique_engagement.editors_picks.post_admin_button",
          className: "npn-editors-pick-button",
          action: () => {
            const genreOptions = (topic.tags || [])
              .filter((tag) => tag !== pickTag && !excludedTags.includes(tag))
              .sort();

            container.lookup("service:modal").show(NpnEditorsPickModal, {
              model: {
                topic: {
                  id: topic.id,
                  title: topic.title,
                  username: post.username,
                  genre_options: genreOptions,
                },
                defaultGenre:
                  genreOptions.length === 1 ? genreOptions[0] : null,
                onPicked: (result) => {
                  container.lookup("service:toasts").success({
                    duration: "short",
                    data: {
                      message: i18n(
                        result.pending
                          ? "npn_critique_engagement.editors_picks.pick_staged"
                          : "npn_critique_engagement.editors_picks.pick_made"
                      ),
                    },
                  });
                },
              },
            });
          },
        };
      });
    });
  },
};
