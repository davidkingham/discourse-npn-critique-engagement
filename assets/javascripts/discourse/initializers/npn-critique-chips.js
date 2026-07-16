import { withPluginApi } from "discourse/lib/plugin-api";

const ICONS = {
  steward: "trophy",
  guide: "award",
  contributor: "medal",
  rising: "seedling",
};

// Renders the recognition chip beside poster names. Positive signals only —
// the serializer never emits anything below the configured chip tier.
export default {
  name: "npn-critique-chips",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (
      !siteSettings.npn_critique_engagement_enabled ||
      !siteSettings.npn_critique_chips_enabled
    ) {
      return;
    }

    const labels = {
      steward: siteSettings.npn_critique_pillar_badge_name,
      guide: siteSettings.npn_critique_supporter_badge_name,
      contributor: siteSettings.npn_critique_contributor_badge_name,
      rising: siteSettings.npn_critique_rising_badge_name,
    };

    withPluginApi((api) => {
      api.addTrackedPostProperties("npn_critique_recognition");

      api.addPosterIcons((cfs, attrs) => {
        const level = attrs.npn_critique_recognition;
        if (!level) {
          return;
        }

        return {
          icon: ICONS[level] ?? "medal",
          text: labels[level],
          title: labels[level],
          className: `npn-critique-chip --${level}`,
        };
      });
    });
  },
};
