import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { userPath } from "discourse/lib/url";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import dBoundAvatarTemplate from "discourse/ui-kit/helpers/d-bound-avatar-template";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import { i18n } from "discourse-i18n";
import NpnTierBadge from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-tier-badge";

export default class NpnAdminOutreach extends Component {
  @service toasts;

  @tracked rowsOverride = null;
  @tracked expandedUserId = null;
  @tracked notes = null;

  get rows() {
    return this.rowsOverride ?? this.args.model.rows;
  }

  @action
  async toggleNotes(row) {
    if (this.expandedUserId === row.user_id) {
      this.expandedUserId = null;
      this.notes = null;
      return;
    }

    this.expandedUserId = row.user_id;
    this.notes = null;
    try {
      const result = await ajax(
        `/admin/plugins/critique-engagement/outreach/${row.user_id}/notes`
      );
      this.notes = result.notes;
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  async saveNote(row, data) {
    try {
      const saved = await ajax(
        "/admin/plugins/critique-engagement/outreach/notes",
        {
          type: "POST",
          data: { user_id: row.user_id, note: data.note },
        }
      );
      this.notes = [saved, ...(this.notes ?? [])];
      this.rowsOverride = this.rows.map((existing) =>
        existing.user_id === row.user_id
          ? { ...existing, last_outreach: saved }
          : existing
      );
      this.toasts.success({
        data: {
          message: i18n("npn_critique_engagement.admin.outreach.note_saved"),
        },
      });
    } catch (error) {
      popupAjaxError(error);
    }
  }

  <template>
    <div class="npn-admin-outreach">
      <DPageSubheader
        @titleLabel={{i18n "npn_critique_engagement.admin.outreach.title"}}
        @descriptionLabel={{i18n
          "npn_critique_engagement.admin.outreach.description"
        }}
      />

      {{#if this.rows.length}}
        <ul class="npn-admin-outreach__list">
          {{#each this.rows as |row|}}
            <li class="npn-admin-outreach__row">
              <div class="npn-admin-outreach__summary">
                <a
                  class="npn-admin-outreach__member"
                  href={{userPath row.username}}
                  data-user-card={{row.username}}
                >
                  {{dBoundAvatarTemplate row.avatar_template "small"}}
                  <span class="npn-admin-outreach__username">
                    {{row.username}}
                  </span>
                </a>
                <NpnTierBadge @tier={{row.tier}} />
                <span class="npn-admin-outreach__counts">
                  {{i18n "npn_critique_engagement.admin.report.shared"}}:
                  {{row.created_topics}}
                  ·
                  {{i18n "npn_critique_engagement.admin.report.critiqued"}}:
                  {{row.topics_replied}}
                </span>
                <span class="npn-admin-outreach__last-contacted">
                  {{#if row.last_outreach}}
                    {{i18n
                      "npn_critique_engagement.admin.outreach.last_contacted"
                    }}
                    {{dFormatDate row.last_outreach.created_at format="tiny"}}
                    (@{{row.last_outreach.staff_username}})
                  {{else}}
                    {{i18n
                      "npn_critique_engagement.admin.outreach.never_contacted"
                    }}
                  {{/if}}
                </span>
                <DButton
                  @action={{fn this.toggleNotes row}}
                  @label="npn_critique_engagement.admin.outreach.add_note"
                  @icon={{if
                    (eq this.expandedUserId row.user_id)
                    "angle-up"
                    "angle-down"
                  }}
                  class="btn-small npn-admin-outreach__toggle"
                />
              </div>

              {{#if (eq this.expandedUserId row.user_id)}}
                <div class="npn-admin-outreach__detail">
                  <Form @onSubmit={{fn this.saveNote row}} as |form|>
                    <form.Field
                      @name="note"
                      @title={{i18n
                        "npn_critique_engagement.admin.outreach.add_note"
                      }}
                      @validation="required"
                      as |field|
                    >
                      <field.Textarea
                        placeholder={{i18n
                          "npn_critique_engagement.admin.outreach.note_placeholder"
                        }}
                      />
                    </form.Field>
                    <form.Submit
                      @label="npn_critique_engagement.admin.outreach.save_note"
                    />
                  </Form>

                  {{#if this.notes.length}}
                    <h4 class="npn-admin-outreach__notes-title">
                      {{i18n
                        "npn_critique_engagement.admin.outreach.notes_title"
                      }}
                    </h4>
                    <ul class="npn-admin-outreach__notes">
                      {{#each this.notes as |note|}}
                        <li class="npn-admin-outreach__note">
                          <span class="npn-admin-outreach__note-meta">
                            @{{note.staff_username}}
                            —
                            {{dFormatDate note.created_at format="medium"}}
                          </span>
                          <p class="npn-admin-outreach__note-text">
                            {{note.note}}
                          </p>
                        </li>
                      {{/each}}
                    </ul>
                  {{/if}}
                </div>
              {{/if}}
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="npn-admin-outreach__empty">
          {{i18n "npn_critique_engagement.admin.outreach.empty"}}
        </p>
      {{/if}}
    </div>
  </template>
}
