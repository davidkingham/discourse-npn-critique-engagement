import Component from "@glimmer/component";
import { service } from "@ember/service";
import NpnCritiqueNudgeBanner from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-critique-nudge-banner";

// The core-composer surface: a new topic being drafted in the critique
// category. Most image posts arrive via /submit instead — that surface has
// its own connector.
export default class NpnCritiqueNudge extends Component {
  @service siteSettings;

  get visible() {
    return (
      this.args.outletArgs.model?.creatingTopic &&
      this.args.outletArgs.model?.categoryId ===
        parseInt(this.siteSettings.npn_critique_category, 10)
    );
  }

  <template><NpnCritiqueNudgeBanner @visible={{this.visible}} /></template>
}
