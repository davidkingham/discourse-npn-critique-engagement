import { withPluginApi } from "discourse/lib/plugin-api";

// The public "selected this as an Editor's Pick" note posted on a topic when
// a moderator makes a pick.
export default {
  name: "npn-critique-post-actions",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.npn_critique_engagement_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.addPostSmallActionIcon("npn_editors_pick", "star");
    });
  },
};
