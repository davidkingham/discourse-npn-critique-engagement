import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import getURL from "discourse/lib/get-url";
import { userPath } from "discourse/lib/url";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import dBoundAvatarTemplate from "discourse/ui-kit/helpers/d-bound-avatar-template";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import { i18n } from "discourse-i18n";
import NpnOutreachTemplateMenu from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-outreach-template-menu";
import NpnTierBadge from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-tier-badge";

function tagUrl(tag) {
  return getURL(`/tag/${tag}`);
}

const OutreachRow = <template>
  <li class="npn-admin-outreach__row">
    <div class="npn-admin-outreach__summary">
      <a
        class="npn-admin-outreach__member"
        href={{userPath @row.username}}
        data-user-card={{@row.username}}
      >
        {{dBoundAvatarTemplate @row.avatar_template "small"}}
        <span class="npn-admin-outreach__username">{{@row.username}}</span>
      </a>
      <NpnTierBadge @tier={{@row.tier}} />
      <span class="npn-admin-outreach__counts">
        {{i18n "npn_critique_engagement.admin.report.shared"}}:
        {{@row.created_topics}}
        ·
        {{i18n "npn_critique_engagement.admin.report.critiqued"}}:
        {{@row.topics_replied}}
      </span>
      {{#if @row.top_tags.length}}
        <span class="npn-admin-outreach__genres">
          {{i18n "npn_critique_engagement.admin.outreach.posts_to"}}
          {{#each @row.top_tags as |genre|}}
            <a class="npn-admin-outreach__genre" href={{tagUrl genre.tag}}>
              {{genre.tag}}
              ×{{genre.count}}
            </a>
          {{/each}}
        </span>
      {{/if}}
      <span class="npn-admin-outreach__last-contacted">
        {{#if @row.last_outreach}}
          {{i18n "npn_critique_engagement.admin.outreach.last_contacted"}}
          {{dFormatDate @row.last_outreach.created_at format="tiny"}}
          (@{{@row.last_outreach.staff_username}})
        {{else}}
          {{i18n "npn_critique_engagement.admin.outreach.never_contacted"}}
        {{/if}}
      </span>
      {{#if @row.claim}}
        {{#if @row.claim.mine}}
          <span class="npn-admin-outreach__claim --mine">
            {{i18n "npn_critique_engagement.admin.outreach.claim_yours"}}
          </span>
          <DButton
            @action={{fn @unclaim @row}}
            @label="npn_critique_engagement.admin.outreach.claim_release"
            class="btn-flat btn-small npn-admin-outreach__unclaim"
          />
        {{else}}
          <span class="npn-admin-outreach__claim">
            {{i18n
              "npn_critique_engagement.admin.outreach.claimed_by"
              username=@row.claim.username
            }}
          </span>
        {{/if}}
      {{else}}
        <DButton
          @action={{fn @claim @row}}
          @label="npn_critique_engagement.admin.outreach.claim"
          @icon="hand-holding-heart"
          class="btn-small npn-admin-outreach__claim-button"
        />
      {{/if}}
      <NpnOutreachTemplateMenu @row={{@row}} />
      <DButton
        @action={{fn @toggleNotes @row}}
        @label="npn_critique_engagement.admin.outreach.add_note"
        @icon={{if (eq @expandedUserId @row.user_id) "angle-up" "angle-down"}}
        class="btn-small npn-admin-outreach__toggle"
      />
    </div>

    {{#if (eq @expandedUserId @row.user_id)}}
      <div class="npn-admin-outreach__detail">
        <Form @onSubmit={{fn @saveNote @row}} as |form|>
          <form.Field
            @name="note"
            @title={{i18n "npn_critique_engagement.admin.outreach.add_note"}}
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

        {{#if @notes.length}}
          <h4 class="npn-admin-outreach__notes-title">
            {{i18n "npn_critique_engagement.admin.outreach.notes_title"}}
          </h4>
          <ul class="npn-admin-outreach__notes">
            {{#each @notes as |note|}}
              <li class="npn-admin-outreach__note">
                <span class="npn-admin-outreach__note-meta">
                  @{{note.staff_username}}
                  —
                  {{dFormatDate note.created_at format="medium"}}
                </span>
                <p class="npn-admin-outreach__note-text">{{note.note}}</p>
              </li>
            {{/each}}
          </ul>
        {{/if}}
      </div>
    {{/if}}
  </li>
</template>;

export default class NpnCritiqueOutreach extends Component {
  @service toasts;

  @tracked rowsOverride = null;
  @tracked welcomeRowsOverride = null;
  @tracked expandedUserId = null;
  @tracked notes = null;

  get rows() {
    return this.rowsOverride ?? this.args.model.rows;
  }

  get welcomeRows() {
    return this.welcomeRowsOverride ?? this.args.model.welcome_rows;
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
      // Logging the contact also resolves any claim.
      this.updateRow(row.user_id, { last_outreach: saved, claim: null });
      this.toasts.success({
        data: {
          message: i18n("npn_critique_engagement.admin.outreach.note_saved"),
        },
      });
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  async claim(row) {
    try {
      const result = await ajax(
        "/admin/plugins/critique-engagement/outreach/claim",
        {
          type: "POST",
          data: { user_id: row.user_id },
        }
      );
      this.updateRow(row.user_id, { claim: result });
    } catch (error) {
      popupAjaxError(error);
      // Someone else likely claimed it first — reload the queues.
      this.refresh();
    }
  }

  @action
  async unclaim(row) {
    try {
      await ajax("/admin/plugins/critique-engagement/outreach/claim", {
        type: "DELETE",
        data: { user_id: row.user_id },
      });
      this.updateRow(row.user_id, { claim: null });
    } catch (error) {
      popupAjaxError(error);
    }
  }

  updateRow(userId, patch) {
    const apply = (existing) =>
      existing.user_id === userId ? { ...existing, ...patch } : existing;
    this.rowsOverride = this.rows.map(apply);
    this.welcomeRowsOverride = this.welcomeRows.map(apply);
  }

  async refresh() {
    try {
      const data = await ajax(
        "/admin/plugins/critique-engagement/outreach.json"
      );
      this.rowsOverride = data.rows;
      this.welcomeRowsOverride = data.welcome_rows;
    } catch {
      // The stale view is still usable; the next visit reloads it anyway.
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
            <OutreachRow
              @row={{row}}
              @expandedUserId={{this.expandedUserId}}
              @notes={{this.notes}}
              @toggleNotes={{this.toggleNotes}}
              @saveNote={{this.saveNote}}
              @claim={{this.claim}}
              @unclaim={{this.unclaim}}
            />
          {{/each}}
        </ul>
      {{else}}
        <p class="npn-admin-outreach__empty">
          {{i18n "npn_critique_engagement.admin.outreach.empty"}}
        </p>
      {{/if}}

      <section class="npn-admin-outreach__welcome">
        <h3>{{i18n "npn_critique_engagement.admin.outreach.welcome_title"}}</h3>
        <p class="npn-admin-outreach__welcome-description">
          {{i18n "npn_critique_engagement.admin.outreach.welcome_description"}}
        </p>
        {{#if this.welcomeRows.length}}
          <ul class="npn-admin-outreach__list">
            {{#each this.welcomeRows as |row|}}
              <OutreachRow
                @row={{row}}
                @expandedUserId={{this.expandedUserId}}
                @notes={{this.notes}}
                @toggleNotes={{this.toggleNotes}}
                @saveNote={{this.saveNote}}
                @claim={{this.claim}}
                @unclaim={{this.unclaim}}
              />
            {{/each}}
          </ul>
        {{else}}
          <p class="npn-admin-outreach__empty">
            {{i18n "npn_critique_engagement.admin.outreach.welcome_empty"}}
          </p>
        {{/if}}
      </section>
    </div>
  </template>
}
