import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import withEventValue from "discourse/helpers/with-event-value";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import DCharCounter from "discourse/ui-kit/d-char-counter";
import DModal from "discourse/ui-kit/d-modal";
import DModalCancel from "discourse/ui-kit/d-modal-cancel";
import DSelect from "discourse/ui-kit/d-select";
import { i18n } from "discourse-i18n";

const REASON_MAX_LENGTH = 1000;

export default class NpnEditorsPickModal extends Component {
  @tracked genre;
  @tracked reason = "";
  @tracked flash;
  @tracked saving = false;

  constructor() {
    super(...arguments);
    this.genre = this.args.model.defaultGenre;
  }

  get topic() {
    return this.args.model.topic;
  }

  get genreOptions() {
    return this.topic.genre_options ?? [];
  }

  get reasonMaxLength() {
    return REASON_MAX_LENGTH;
  }

  get submitDisabled() {
    return (
      this.saving ||
      (this.genreOptions.length > 0 && !this.genre) ||
      this.reason.length > REASON_MAX_LENGTH
    );
  }

  @action
  setGenre(genre) {
    this.genre = genre;
  }

  @action
  setReason(reason) {
    this.flash = null;
    this.reason = reason;
  }

  @action
  async submit() {
    this.saving = true;
    try {
      const data = { topic_id: this.topic.id };
      if (this.genre) {
        data.genre = this.genre;
      }
      const reason = this.reason.trim();
      if (reason) {
        data.reason = reason;
      }
      const result = await ajax("/moderate/editors-picks/pick", {
        type: "POST",
        data,
      });
      this.args.model.onPicked(result);
      this.args.closeModal();
    } catch (error) {
      this.flash = extractError(error);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <DModal
      @closeModal={{@closeModal}}
      @title={{i18n "npn_critique_engagement.editors_picks.pick_modal.title"}}
      @flash={{this.flash}}
      class="npn-editors-pick-modal"
    >
      <:body>
        <p class="npn-editors-pick-modal__topic">
          {{this.topic.title}}
          — @{{this.topic.username}}
        </p>

        {{#if this.genreOptions.length}}
          <div class="npn-editors-pick-modal__field">
            <label for="npn-pick-genre">
              {{i18n
                "npn_critique_engagement.editors_picks.pick_modal.genre_label"
              }}
            </label>
            <DSelect
              @value={{this.genre}}
              @onChange={{this.setGenre}}
              id="npn-pick-genre"
              as |select|
            >
              {{#each this.genreOptions as |tag|}}
                <select.Option @value={{tag}}>{{tag}}</select.Option>
              {{/each}}
            </DSelect>
            <p class="npn-editors-pick-modal__hint">
              {{i18n
                "npn_critique_engagement.editors_picks.pick_modal.genre_hint"
              }}
            </p>
          </div>
        {{/if}}

        <div class="npn-editors-pick-modal__field">
          <label for="npn-pick-reason">
            {{i18n
              "npn_critique_engagement.editors_picks.pick_modal.reason_label"
            }}
          </label>
          <DCharCounter @value={{this.reason}} @max={{this.reasonMaxLength}}>
            <textarea
              {{on "input" (withEventValue this.setReason)}}
              id="npn-pick-reason"
              class="npn-editors-pick-modal__reason"
              placeholder={{i18n
                "npn_critique_engagement.editors_picks.pick_modal.reason_placeholder"
              }}
            >{{this.reason}}</textarea>
          </DCharCounter>
          <p class="npn-editors-pick-modal__hint">
            {{i18n
              "npn_critique_engagement.editors_picks.pick_modal.reason_hint"
            }}
          </p>
        </div>
      </:body>
      <:footer>
        <DButton
          @action={{this.submit}}
          @icon="star"
          @label="npn_critique_engagement.editors_picks.pick_modal.submit"
          @disabled={{this.submitDisabled}}
          class="btn-primary"
        />
        <DModalCancel @close={{@closeModal}} />
      </:footer>
    </DModal>
  </template>
}
