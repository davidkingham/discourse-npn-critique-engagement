import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import {
  recognitionClass,
  recognitionIcon,
  recognitionLabel,
} from "../lib/recognition-chips";

// Public recognition chip.
export default class NpnCritiqueChip extends Component {
  @service siteSettings;

  get label() {
    return recognitionLabel(this.siteSettings, this.args.level);
  }

  get icon() {
    return recognitionIcon(this.args.level);
  }

  get chipClass() {
    return recognitionClass(this.args.level);
  }

  <template>
    <span class={{this.chipClass}} ...attributes>
      {{dIcon this.icon}}
      <span class="npn-critique-chip__label">{{this.label}}</span>
    </span>
  </template>
}
