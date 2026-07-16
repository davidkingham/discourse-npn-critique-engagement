import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";

const ICONS = {
  steward: "trophy",
  guide: "award",
  contributor: "medal",
};

// Public recognition chip. Labels come from the badge-name settings so the
// chip, the badge, and the hall of fame always agree.
export default class NpnCritiqueChip extends Component {
  @service siteSettings;

  get label() {
    switch (this.args.level) {
      case "steward":
        return this.siteSettings.npn_critique_pillar_badge_name;
      case "guide":
        return this.siteSettings.npn_critique_supporter_badge_name;
      default:
        return this.siteSettings.npn_critique_contributor_badge_name;
    }
  }

  get icon() {
    return ICONS[this.args.level] ?? "medal";
  }

  <template>
    <span class="npn-critique-chip --{{@level}}" ...attributes>
      {{dIcon this.icon}}
      <span class="npn-critique-chip__label">{{this.label}}</span>
    </span>
  </template>
}
