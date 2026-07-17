import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

// Staff see the moderator dashboard in the sidebar's community section —
// the one bookmark they'd otherwise need.
export default {
  name: "npn-critique-sidebar",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    const currentUser = container.lookup("service:current-user");
    if (!siteSettings.npn_critique_engagement_enabled || !currentUser?.staff) {
      return;
    }

    withPluginApi((api) => {
      api.addCommunitySectionLink({
        name: "npn-moderate",
        route: "critique-moderate",
        title: i18n("npn_critique_engagement.moderate.sidebar_title"),
        text: i18n("npn_critique_engagement.moderate.sidebar_text"),
        icon: "hand-holding-heart",
      });
    });
  },
};
