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

// "Indefinitely" is the common case and so leads; the timed options cover
// "give them room for a while" without needing a second feature.
const PREFIX = "npn_critique_engagement.admin.outreach.exclude_modal";
const DURATIONS = [
  { value: "", key: `${PREFIX}.duration_indefinite` },
  { value: "90", key: `${PREFIX}.duration_90_days` },
  { value: "180", key: `${PREFIX}.duration_180_days` },
  { value: "365", key: `${PREFIX}.duration_365_days` },
];

export default class NpnOutreachExclusionModal extends Component {
  @tracked reason = "";
  @tracked days = "";
  @tracked flash;
  @tracked saving = false;

  get row() {
    return this.args.model.row;
  }

  get durations() {
    return DURATIONS;
  }

  get reasonMaxLength() {
    return REASON_MAX_LENGTH;
  }

  get submitDisabled() {
    return (
      this.saving ||
      !this.reason.trim() ||
      this.reason.length > REASON_MAX_LENGTH
    );
  }

  @action
  setReason(reason) {
    this.flash = null;
    this.reason = reason;
  }

  @action
  setDays(days) {
    this.days = days;
  }

  @action
  async submit() {
    this.saving = true;
    try {
      const data = { user_id: this.row.user_id, reason: this.reason.trim() };
      if (this.days) {
        data.days = this.days;
      }
      const result = await ajax(
        "/admin/plugins/critique-engagement/outreach/exclusion",
        { type: "POST", data }
      );
      this.args.model.onExcluded(result);
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
      @title={{i18n
        "npn_critique_engagement.admin.outreach.exclude_modal.title"
      }}
      @flash={{this.flash}}
      class="npn-outreach-exclusion-modal"
    >
      <:body>
        <p class="npn-outreach-exclusion-modal__member">
          @{{this.row.username}}
        </p>
        <p class="npn-outreach-exclusion-modal__explanation">
          {{i18n
            "npn_critique_engagement.admin.outreach.exclude_modal.explanation"
          }}
        </p>

        <div class="npn-outreach-exclusion-modal__field">
          <label for="npn-exclusion-reason">
            {{i18n
              "npn_critique_engagement.admin.outreach.exclude_modal.reason_label"
            }}
          </label>
          <DCharCounter @value={{this.reason}} @max={{this.reasonMaxLength}}>
            <textarea
              {{on "input" (withEventValue this.setReason)}}
              id="npn-exclusion-reason"
              class="npn-outreach-exclusion-modal__reason"
              placeholder={{i18n
                "npn_critique_engagement.admin.outreach.exclude_modal.reason_placeholder"
              }}
            >{{this.reason}}</textarea>
          </DCharCounter>
          <p class="npn-outreach-exclusion-modal__hint">
            {{i18n
              "npn_critique_engagement.admin.outreach.exclude_modal.reason_hint"
            }}
          </p>
        </div>

        <div class="npn-outreach-exclusion-modal__field">
          <label for="npn-exclusion-duration">
            {{i18n
              "npn_critique_engagement.admin.outreach.exclude_modal.duration_label"
            }}
          </label>
          <DSelect
            @value={{this.days}}
            @onChange={{this.setDays}}
            id="npn-exclusion-duration"
            as |select|
          >
            {{#each this.durations as |duration|}}
              <select.Option @value={{duration.value}}>
                {{i18n duration.key}}
              </select.Option>
            {{/each}}
          </DSelect>
        </div>
      </:body>
      <:footer>
        <DButton
          @action={{this.submit}}
          @icon="circle-pause"
          @label="npn_critique_engagement.admin.outreach.exclude_modal.submit"
          @disabled={{this.submitDisabled}}
          class="btn-primary"
        />
        <DModalCancel @close={{@closeModal}} />
      </:footer>
    </DModal>
  </template>
}
