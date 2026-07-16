import Component from "@glimmer/component";
import { service } from "@ember/service";
import DNavigationItem from "discourse/ui-kit/d-navigation-item";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class NpnCritiqueImpactLink extends Component {
  @service currentUser;
  @service siteSettings;

  // The impact panel is private, so the tab only exists on your own profile.
  get shown() {
    return (
      this.siteSettings.npn_critique_engagement_enabled &&
      this.currentUser &&
      this.args.outletArgs.model?.id === this.currentUser.id
    );
  }

  <template>
    {{#if this.shown}}
      <DNavigationItem
        @route="user.critique-impact"
        class="user-nav__critique-impact"
      >
        {{dIcon "hand-holding-heart"}}
        <span>{{i18n "npn_critique_engagement.impact.nav_label"}}</span>
      </DNavigationItem>
    {{/if}}
  </template>
}
