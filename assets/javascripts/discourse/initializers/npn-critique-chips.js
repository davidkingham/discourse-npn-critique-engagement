import { withPluginApi } from "discourse/lib/plugin-api";
import {
  GIVEN_CHIP_CLASS,
  GIVEN_CHIP_ICON,
  givenChipLabel,
  givenChipText,
  recognitionClass,
  recognitionIcon,
  recognitionLabel,
} from "../lib/recognition-chips";

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

    withPluginApi((api) => {
      if (chipsEnabled) {
        api.addTrackedPostProperties("npn_critique_recognition");

        api.addPosterIcons((cfs, attrs) => {
          const level = attrs.npn_critique_recognition;
          if (!level) {
            return;
          }

          const label = recognitionLabel(siteSettings, level);

          return {
            icon: recognitionIcon(level),
            text: label,
            title: label,
            className: recognitionClass(level),
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
            icon: GIVEN_CHIP_ICON,
            text: givenChipText(count),
            title: givenChipLabel(siteSettings, count),
            className: GIVEN_CHIP_CLASS,
          };
        });
      }
    });
  },
};
