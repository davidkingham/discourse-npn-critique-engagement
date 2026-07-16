import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-npn-critique-engagement";

export default {
  name: "npn-critique-engagement-admin-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "hand-holding-heart");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "npn_critique_engagement.admin.report.nav_label",
          route: "adminPlugins.show.discourse-npn-critique-engagement-report",
          description: "npn_critique_engagement.admin.report.nav_description",
        },
        {
          label: "npn_critique_engagement.admin.health.nav_label",
          route: "adminPlugins.show.discourse-npn-critique-engagement-health",
          description: "npn_critique_engagement.admin.health.nav_description",
        },
      ]);
    });
  },
};
