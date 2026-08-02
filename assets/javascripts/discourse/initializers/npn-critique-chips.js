import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

const ICONS = {
  steward: "trophy",
  guide: "award",
  contributor: "medal",
  rising: "seedling",
};

// Renders the recognition chip and the give-and-take count beside poster
// names. Positive signals only — the serializers never emit anything below
// the configured chip tier or the given-count floor.
export default {
  name: "npn-critique-chips",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.npn_critique_engagement_enabled) {
      return;
    }

    const chipsEnabled = siteSettings.npn_critique_chips_enabled;
    const givenChipEnabled = siteSettings.npn_critique_given_chip_enabled;
    if (!chipsEnabled && !givenChipEnabled) {
      return;
    }

    const labels = {
      steward: siteSettings.npn_critique_pillar_badge_name,
      guide: siteSettings.npn_critique_supporter_badge_name,
      contributor: siteSettings.npn_critique_contributor_badge_name,
      rising: siteSettings.npn_critique_rising_badge_name,
    };

    withPluginApi((api) => {
      if (chipsEnabled) {
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
      }

      if (givenChipEnabled) {
        api.addTrackedPostProperties("npn_critique_given_recently");

        api.addPosterIcons((cfs, attrs) => {
          const count = attrs.npn_critique_given_recently;
          if (!count) {
            return;
          }

          return {
            icon: "hand-holding-heart",
            text: String(count),
            title: i18n("npn_critique_engagement.given_chip.label", { count }),
            className: "npn-given-chip",
          };
        });
      }
    });
  },
};
