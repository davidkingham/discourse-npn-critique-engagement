import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

// Sidebar links: the leaderboard and hall of fame for everyone, the
// moderator dashboard for staff.
export default {
  name: "npn-critique-sidebar",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    const currentUser = container.lookup("service:current-user");
    if (!siteSettings.npn_critique_engagement_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.addCommunitySectionLink(
        {
          name: "npn-critique-leaderboard",
          route: "critique-leaderboard",
          title: i18n("npn_critique_engagement.leaderboard.sidebar_title"),
          text: i18n("npn_critique_engagement.leaderboard.sidebar_text"),
          icon: "ranking-star",
        },
        true
      );
      api.addCommunitySectionLink(
        {
          name: "npn-hall-of-fame",
          route: "critique-hall-of-fame",
          title: i18n("npn_critique_engagement.hall_of_fame.sidebar_title"),
          text: i18n("npn_critique_engagement.hall_of_fame.sidebar_text"),
          icon: "trophy",
        },
        true
      );

      if (currentUser?.staff) {
        api.addCommunitySectionLink({
          name: "npn-moderate",
          route: "critique-moderate",
          title: i18n("npn_critique_engagement.moderate.sidebar_title"),
          text: i18n("npn_critique_engagement.moderate.sidebar_text"),
          icon: "hand-holding-heart",
        });
      }
    });
  },
};
