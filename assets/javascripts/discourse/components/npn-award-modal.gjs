import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import DModalCancel from "discourse/ui-kit/d-modal-cancel";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dEmoji from "discourse/ui-kit/helpers/d-emoji";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import {
  awardMenu,
  awardReactionIds,
  currentAwardId,
  isTopicOwner,
  reactionCount,
} from "../lib/awards";

// The "Give an award" modal behind the post-menu award button.
//
// Each award is named and explained here rather than left as a bare emoji
// in the reactions picker: which award fits a critique is a judgement the
// giver has to make, and they can only make it if they know what the
// awards mean.
export default class NpnAwardModal extends Component {
  @service appEvents;
  @service currentUser;
  @service siteSettings;

  @tracked saving = false;
  @tracked flash;

  get post() {
    return this.args.model.post;
  }

  get awardIds() {
    return awardReactionIds(this.siteSettings);
  }

  get isOwner() {
    return isTopicOwner(this.post, this.currentUser);
  }

  get awards() {
    const given = currentAwardId(this.post, this.awardIds);
    const canAct = this.canAct;
    const isOwner = this.isOwner;

    return awardMenu(this.siteSettings)
      .filter((award) => !award.ownerOnly || isOwner)
      .map((award) => {
        const isGiven = award.id === given;
        let title;

        if (!canAct) {
          title = i18n("npn_critique_engagement.awards.modal.locked");
        } else if (isGiven) {
          title = i18n("npn_critique_engagement.awards.modal.remove", {
            award: award.label,
          });
        } else {
          title = i18n("npn_critique_engagement.awards.modal.give", {
            award: award.label,
          });
        }

        return {
          ...award,
          title,
          given: isGiven,
          count: reactionCount(this.post, award.id),
        };
      });
  }

  // Reactions allow one reaction per member per post, so an award takes the
  // place of whatever that member already left. Say so up front rather than
  // let someone's like disappear without explanation.
  get replacesReaction() {
    const current = this.post.current_user_reaction;
    return !!current && !this.awardIds.includes(current.id);
  }

  get canAct() {
    if (this.post.topic?.archived) {
      return false;
    }
    // Past the undo window a reaction is locked, so it can be neither
    // removed nor swapped for an award.
    const current = this.post.current_user_reaction;
    if (current && !current.can_undo) {
      return false;
    }
    return !!this.post.likeAction?.canToggle;
  }

  get disabled() {
    return this.saving || !this.canAct;
  }

  @action
  async toggle(award) {
    if (this.disabled) {
      return;
    }

    this.saving = true;
    this.flash = null;

    try {
      const result = await ajax(
        `/discourse-reactions/posts/${this.post.id}/custom-reactions/${award.id}/toggle.json`,
        { type: "PUT" }
      );
      this.applyResult(result);
      this.args.closeModal();
    } catch (error) {
      this.flash = extractError(error);
    } finally {
      this.saving = false;
    }
  }

  // The toggle endpoint returns the post freshly serialized. Copying the
  // four reaction fields back is what keeps the reactions button, the
  // reaction list under the post, and the award button in sync without a
  // reload — discourse-reactions marks all four as tracked post properties.
  applyResult(result) {
    const post = this.post;
    post.reactions = result.reactions ?? [];
    post.current_user_reaction = result.current_user_reaction ?? null;
    post.current_user_used_main_reaction =
      !!result.current_user_used_main_reaction;
    post.reaction_users_count = result.reaction_users_count ?? 0;

    this.appEvents.trigger("discourse-reactions:reaction-toggled", {
      post: result,
      reaction: result.current_user_reaction,
    });
  }

  <template>
    <DModal
      @closeModal={{@closeModal}}
      @title={{i18n "npn_critique_engagement.awards.modal.title"}}
      @flash={{this.flash}}
      class="npn-award-modal"
    >
      <:body>
        <p class="npn-award-modal__intro">
          {{i18n "npn_critique_engagement.awards.modal.intro"}}
        </p>

        {{#if this.canAct}}
          {{#if this.replacesReaction}}
            <p class="npn-award-modal__note">
              {{i18n "npn_critique_engagement.awards.modal.replaces_reaction"}}
            </p>
          {{/if}}
        {{else}}
          <p class="npn-award-modal__note">
            {{i18n "npn_critique_engagement.awards.modal.locked"}}
          </p>
        {{/if}}

        <ul class="npn-award-modal__list">
          {{#each this.awards as |award|}}
            <li class="npn-award-modal__item">
              <DButton
                class={{dConcatClass
                  "npn-award-modal__award"
                  "btn-flat"
                  (if award.given "--given")
                }}
                data-award={{award.id}}
                @action={{fn this.toggle award}}
                @disabled={{this.disabled}}
                @translatedTitle={{award.title}}
              >
                <span class="npn-award-modal__emoji">{{dEmoji award.id}}</span>
                <span class="npn-award-modal__text">
                  <span class="npn-award-modal__label">{{award.label}}</span>
                  {{#if award.description}}
                    <span
                      class="npn-award-modal__description"
                    >{{award.description}}</span>
                  {{/if}}
                  {{#if award.ownerOnly}}
                    <span class="npn-award-modal__owner-only">
                      {{i18n "npn_critique_engagement.awards.modal.owner_only"}}
                    </span>
                  {{/if}}
                </span>
                <span class="npn-award-modal__state">
                  {{#if award.given}}
                    {{dIcon "check"}}
                  {{/if}}
                  {{#if award.count}}
                    <span class="npn-award-modal__count">{{award.count}}</span>
                  {{/if}}
                </span>
              </DButton>
            </li>
          {{/each}}
        </ul>
      </:body>
      <:footer>
        <DModalCancel @close={{@closeModal}} />
      </:footer>
    </DModal>
  </template>
}
