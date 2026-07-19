import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DMenu from "discourse/float-kit/components/d-menu";
import { clipboardCopy } from "discourse/lib/utilities";
import DButton from "discourse/ui-kit/d-button";
import DDropdownMenu from "discourse/ui-kit/d-dropdown-menu";
import { i18n } from "discourse-i18n";

const TEMPLATE_KEYS = ["welcome", "nudge", "soft_nudge", "followup"];

// "Copy template" on an outreach row: starting-point DM texts with the
// member's and moderator's names filled in. The texts live in client.en.yml
// so staff can reword them under Customize > Text without a deploy.
export default class NpnOutreachTemplateMenu extends Component {
  @service currentUser;
  @service toasts;

  get templates() {
    return TEMPLATE_KEYS.map((key) => ({
      key,
      label: `npn_critique_engagement.admin.outreach.template_labels.${key}`,
    }));
  }

  @action
  onRegisterApi(api) {
    this.dMenu = api;
  }

  @action
  copy(key) {
    const text = i18n(
      `npn_critique_engagement.admin.outreach.templates.${key}`,
      {
        name: this.args.row.username,
        mod_name: this.currentUser.username,
      }
    );
    clipboardCopy(text);
    this.toasts.success({
      data: {
        message: i18n("npn_critique_engagement.admin.outreach.template_copied"),
      },
    });
    this.dMenu?.close();
  }

  <template>
    <DMenu
      @identifier="npn-outreach-template-menu"
      @modalForMobile={{true}}
      @icon="copy"
      @label={{i18n "npn_critique_engagement.admin.outreach.copy_template"}}
      @onRegisterApi={{this.onRegisterApi}}
      @triggerClass="btn-small npn-admin-outreach__template-trigger"
      class="npn-admin-outreach__template-menu"
    >
      <:content>
        <DDropdownMenu as |dropdown|>
          {{#each this.templates as |template|}}
            <dropdown.item>
              <DButton
                @label={{template.label}}
                @action={{fn this.copy template.key}}
                class="btn-transparent"
              />
            </dropdown.item>
          {{/each}}
        </DDropdownMenu>
      </:content>
    </DMenu>
  </template>
}
