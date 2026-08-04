import { withPluginApi } from "discourse/lib/plugin-api";
import NpnAwardButton from "../components/npn-award-button";
import { awardMenu } from "../lib/awards";

// Registers the "Award" post-menu button next to the reactions button.
//
// Awards are reactions, so this needs discourse-reactions to be installed
// and enabled — but nothing here imports from it. The toggle endpoint is
// called by URL from the modal, which keeps this plugin's JS loading on a
// site that has no reactions plugin instead of failing at boot on a missing
// module.
export default {
  name: "npn-award-button",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    if (
      !siteSettings.npn_critique_engagement_enabled ||
      !siteSettings.npn_critique_award_button_enabled ||
      !siteSettings.discourse_reactions_enabled
    ) {
      return;
    }

    const categoryId = parseInt(siteSettings.npn_critique_category, 10);
    if (!categoryId) {
      return;
    }

    // No award is offerable — every entry in the menu setting names an
    // emoji the reactions plugin would reject — so there is nothing for the
    // button to do.
    if (awardMenu(siteSettings).length === 0) {
      return;
    }

    const site = container.lookup("service:site");

    const inCritiqueCategory = (topic) => {
      if (!topic) {
        return false;
      }
      if (topic.category_id === categoryId) {
        return true;
      }
      const category = site.categories.find((c) => c.id === topic.category_id);
      return category?.parent_category_id === categoryId;
    };

    withPluginApi((api) => {
      const currentUser = api.getCurrentUser();
      if (!currentUser) {
        return;
      }

      api.registerValueTransformer(
        "post-menu-buttons",
        ({ value: dag, context: { post, buttonKeys } }) => {
          // Replies only. The first post is the photo being critiqued, and
          // the scorer never counts an award on it — offering the button
          // there would advertise an honor that goes nowhere.
          if (post?.post_number <= 1 || !inCritiqueCategory(post?.topic)) {
            return;
          }

          // Left of the like button, so the honor reads first rather than
          // trailing the everyday reaction.
          dag.add("npn-award", NpnAwardButton, { before: [buttonKeys.LIKE] });
        }
      );
    });
  },
};
