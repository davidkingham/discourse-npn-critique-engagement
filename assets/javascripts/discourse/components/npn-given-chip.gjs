import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import {
  GIVEN_CHIP_CLASS,
  GIVEN_CHIP_ICON,
  givenChipLabel,
} from "../lib/recognition-chips";

// The public give-and-take count. The serialized number is a band floor, so
// the copy reads "N+" and never publishes an exact figure.
export default class NpnGivenChip extends Component {
  @service siteSettings;

  get label() {
    return givenChipLabel(this.siteSettings, this.args.count);
  }

  <template>
    <span class={{GIVEN_CHIP_CLASS}} ...attributes>
      {{dIcon GIVEN_CHIP_ICON}}
      <span class="npn-given-chip__label">{{this.label}}</span>
    </span>
  </template>
}
