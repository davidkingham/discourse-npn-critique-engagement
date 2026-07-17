import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import KeyValueStore from "discourse/lib/key-value-store";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const STORE_NAMESPACE = "npn_critique_";

// The soft-gating banner: informs, never blocks. Rendered wherever a member
// starts a new critique-category topic (the core composer and the /submit
// flow); the caller decides context via @visible, this component owns
// eligibility, copy, dismissal, and the once-per-day suppression — shared
// across every surface via one store key.
export default class NpnCritiqueNudgeBanner extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked dismissed = false;

  store = new KeyValueStore(STORE_NAMESPACE);

  // Once-per-day suppression is decided when the surface opens, then the
  // banner stays for the whole session (marking it shown mid-session must
  // not hide it while the member is reading it).
  suppressedToday = this.store.get(this.storeKey) === this.todayKey;

  get storeKey() {
    return `nudge-day-${this.currentUser?.id}`;
  }

  get todayKey() {
    return new Date().toDateString();
  }

  get nudgeData() {
    return this.currentUser?.npn_critique_nudge;
  }

  get shown() {
    return (
      this.args.visible &&
      !this.dismissed &&
      !this.suppressedToday &&
      this.nudgeData
    );
  }

  get message() {
    const shared = this.nudgeData.created_topics;
    const critiqued = this.nudgeData.topics_replied;
    const custom = this.siteSettings.npn_critique_nudge_copy;

    if (custom) {
      return custom
        .replaceAll("%{shared}", shared)
        .replaceAll("%{critiqued}", critiqued);
    }
    return i18n("npn_critique_engagement.nudge.copy", { shared, critiqued });
  }

  @action
  markShown() {
    this.store.set({ key: this.storeKey, value: this.todayKey });
  }

  @action
  dismiss() {
    this.dismissed = true;
  }

  <template>
    {{#if this.shown}}
      <div class="npn-critique-nudge" role="note" {{didInsert this.markShown}}>
        {{dIcon "hand-holding-heart"}}
        <p class="npn-critique-nudge__message">{{this.message}}</p>
        <DButton
          @action={{this.dismiss}}
          @icon="xmark"
          @ariaLabel="npn_critique_engagement.nudge.dismiss"
          class="btn-transparent npn-critique-nudge__dismiss"
        />
      </div>
    {{/if}}
  </template>
}
