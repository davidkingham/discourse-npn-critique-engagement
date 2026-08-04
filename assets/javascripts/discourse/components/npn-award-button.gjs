import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import { i18n } from "discourse-i18n";
import { awardCount, awardReactionIds, currentAwardId } from "../lib/awards";
import NpnAwardModal from "./npn-award-modal";

// Post-menu button: "Award".
//
// Awards are reactions, so before this button the only way to give one was
// to hover the heart and find the right rosette in the picker — which is
// why almost nobody did. This puts them on their own button next to the
// reactions button and opens a modal that names each award, so a member
// learns what they mean on the way to giving one.
//
// Visibility is gated twice, the same belt-and-braces the other post-menu
// buttons in this codebase use: the initializer decides whether to add the
// button to the DAG at all (settings, category, post number, signed in),
// and `shouldRender` re-checks the per-render post state so the button
// disappears cleanly when it stops applying.
//
// The button only renders for viewers who can actually give an award. The
// awards a post has already received are visible to everyone in the
// reaction list under the post, so nothing is hidden by that; this button
// is the give-an-award entry point, and an inert one would only add noise.
export default class NpnAwardButton extends Component {
  static shouldRender(args) {
    const post = args?.post;
    if (!post) {
      return false;
    }
    // Nobody can react to their own post, and archived topics reject
    // reactions server-side.
    if (post.yours || post.topic?.archived) {
      return false;
    }
    return true;
  }

  @service modal;
  @service siteSettings;

  get awardIds() {
    return awardReactionIds(this.siteSettings);
  }

  get count() {
    return awardCount(this.args.post, this.awardIds);
  }

  get givenAward() {
    return currentAwardId(this.args.post, this.awardIds);
  }

  get title() {
    if (this.givenAward) {
      return i18n("npn_critique_engagement.awards.button.title_given");
    }
    return i18n("npn_critique_engagement.awards.button.title");
  }

  @action
  openAwardModal() {
    this.modal.show(NpnAwardModal, { model: { post: this.args.post } });
  }

  <template>
    <DButton
      class={{dConcatClass
        "post-action-menu__npn-award"
        "npn-award-button"
        (if this.givenAward "--given")
      }}
      ...attributes
      @action={{this.openAwardModal}}
      @icon="award"
      @label={{if @showLabel "npn_critique_engagement.awards.button.label"}}
      @translatedTitle={{this.title}}
      @translatedAriaLabel={{this.title}}
    >
      {{#if this.count}}
        <span class="npn-award-button__count">{{this.count}}</span>
      {{/if}}
    </DButton>
  </template>
}
