import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import getURL from "discourse/lib/get-url";
import { userPath } from "discourse/lib/url";
import DButton from "discourse/ui-kit/d-button";
import dBoundAvatarTemplate from "discourse/ui-kit/helpers/d-bound-avatar-template";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import NpnTierBadge from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-tier-badge";

function rowClass(topic) {
  return `npn-moderate__coverage-row ${topic.new_member ? "--urgent" : ""}`;
}

function tagUrl(tag) {
  return getURL(`/tag/${tag}`);
}

export default class NpnModerateDashboard extends Component {
  @tracked pickStatusOverride = null;

  get pickStatus() {
    return this.pickStatusOverride ?? this.args.model.pick_status;
  }

  @action
  async declareNoPick(genre) {
    try {
      const result = await ajax("/moderate/editors-picks/no-pick", {
        type: "POST",
        data: { genre: genre.tag },
      });
      this.patchGenre(genre.tag, { no_pick: { username: result.username } });
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  async undoNoPick(genre) {
    try {
      await ajax("/moderate/editors-picks/no-pick", {
        type: "DELETE",
        data: { genre: genre.tag },
      });
      this.patchGenre(genre.tag, { no_pick: null });
    } catch (error) {
      popupAjaxError(error);
    }
  }

  patchGenre(tag, patch) {
    this.pickStatusOverride = this.pickStatus.map((existing) =>
      existing.tag === tag ? { ...existing, ...patch } : existing
    );
  }

  <template>
    <section class="npn-moderate">
    <header class="npn-moderate__header">
      <h1 class="npn-moderate__title">
        {{dIcon "hand-holding-heart"}}
        {{i18n "npn_critique_engagement.moderate.title"}}
      </h1>
      <p class="npn-moderate__description">
        {{i18n "npn_critique_engagement.moderate.description"}}
      </p>
      <LinkTo @route="critique-report" class="npn-moderate__report-link">
        {{i18n "npn_critique_engagement.moderate.report_link"}}
        {{dIcon "chevron-right"}}
      </LinkTo>
    </header>

    <div class="npn-moderate__panels">
      <section class="npn-moderate__panel npn-moderate__coverage">
        <h2>
          {{i18n "npn_critique_engagement.moderate.coverage_title"}}
          <span class="npn-moderate__count">{{@model.coverage.total}}</span>
        </h2>
        <p class="npn-moderate__hint">
          {{i18n "npn_critique_engagement.moderate.coverage_hint"}}
        </p>
        {{#if @model.coverage.topics.length}}
          <ul class="npn-moderate__coverage-list">
            {{#each @model.coverage.topics as |topic|}}
              <li class={{rowClass topic}}>
                <a class="npn-moderate__thumb-link" href={{topic.url}}>
                  {{#if topic.image_url}}
                    <img
                      class="npn-moderate__thumb"
                      src={{topic.image_url}}
                      alt=""
                      loading="lazy"
                    />
                  {{else}}
                    <div class="npn-moderate__thumb --placeholder">
                      {{dIcon "image"}}
                    </div>
                  {{/if}}
                </a>
                <div class="npn-moderate__coverage-body">
                  <a class="npn-moderate__topic" href={{topic.url}}>
                    {{topic.title}}
                  </a>
                  <div class="npn-moderate__coverage-meta">
                    <a
                      class="npn-moderate__member"
                      href={{userPath topic.username}}
                      data-user-card={{topic.username}}
                    >
                      {{dBoundAvatarTemplate topic.avatar_template "tiny"}}
                      <span>{{topic.username}}</span>
                    </a>
                    {{#if topic.tier}}
                      <NpnTierBadge @tier={{topic.tier}} />
                    {{/if}}
                    {{#if topic.score}}
                      <span class="npn-moderate__score">{{topic.score}}</span>
                    {{/if}}
                    {{#each topic.tags as |tag|}}
                      <a class="npn-moderate__tag" href={{tagUrl tag}}>
                        {{tag}}
                      </a>
                    {{/each}}
                    <span class="npn-moderate__age">
                      {{dFormatDate topic.created_at format="tiny"}}
                    </span>
                  </div>
                </div>
              </li>
            {{/each}}
          </ul>
        {{else}}
          <p class="npn-moderate__empty">
            {{i18n "npn_critique_engagement.moderate.coverage_empty"}}
          </p>
        {{/if}}
      </section>

      <section class="npn-moderate__panel npn-moderate__new-members">
        <h2>
          {{i18n "npn_critique_engagement.moderate.new_members_title"}}
          <span class="npn-moderate__count">{{@model.new_members.total}}</span>
        </h2>
        <p class="npn-moderate__hint">
          {{i18n "npn_critique_engagement.moderate.new_members_hint"}}
        </p>
        {{#if @model.new_members.topics.length}}
          <ul class="npn-moderate__coverage-list">
            {{#each @model.new_members.topics as |topic|}}
              <li class="npn-moderate__coverage-row --urgent">
                <a class="npn-moderate__thumb-link" href={{topic.url}}>
                  {{#if topic.image_url}}
                    <img
                      class="npn-moderate__thumb"
                      src={{topic.image_url}}
                      alt=""
                      loading="lazy"
                    />
                  {{else}}
                    <div class="npn-moderate__thumb --placeholder">
                      {{dIcon "seedling"}}
                    </div>
                  {{/if}}
                </a>
                <div class="npn-moderate__coverage-body">
                  <a class="npn-moderate__topic" href={{topic.url}}>
                    {{topic.title}}
                  </a>
                  <div class="npn-moderate__coverage-meta">
                    <a
                      class="npn-moderate__member"
                      href={{userPath topic.username}}
                      data-user-card={{topic.username}}
                    >
                      {{dBoundAvatarTemplate topic.avatar_template "tiny"}}
                      <span>{{topic.username}}</span>
                    </a>
                    <span class="npn-moderate__subcategory">
                      {{topic.subcategory}}
                    </span>
                    <span class="npn-moderate__replies">
                      {{i18n
                        "npn_critique_engagement.moderate.reply_count"
                        count=topic.replies
                      }}
                    </span>
                    <span class="npn-moderate__age">
                      {{dFormatDate topic.created_at format="tiny"}}
                    </span>
                  </div>
                </div>
              </li>
            {{/each}}
          </ul>
        {{else}}
          <p class="npn-moderate__empty">
            {{i18n "npn_critique_engagement.moderate.new_members_empty"}}
          </p>
        {{/if}}
      </section>

      <div class="npn-moderate__side">
        <section class="npn-moderate__panel npn-moderate__picks">
          <h2>{{i18n "npn_critique_engagement.moderate.picks_title"}}</h2>
          <p class="npn-moderate__hint">
            {{i18n "npn_critique_engagement.moderate.picks_hint"}}
          </p>
          {{#if this.pickStatus.length}}
            <ul class="npn-moderate__pick-list">
              {{#each this.pickStatus as |genre|}}
                <li class="npn-moderate__pick-row">
                  <LinkTo
                    @route="critique-editors-picks"
                    @query={{hash tag=genre.tag}}
                    class="npn-moderate__pick-tag"
                  >
                    {{genre.tag}}
                  </LinkTo>
                  {{#if genre.picked}}
                    <a class="npn-moderate__pick-done" href={{genre.topic_url}}>
                      {{dIcon "check"}}
                      {{i18n
                        "npn_critique_engagement.moderate.picked_by"
                        username=genre.picked_by
                      }}
                    </a>
                  {{else if genre.no_pick}}
                    <span class="npn-moderate__pick-none">
                      {{dIcon "ban"}}
                      {{i18n
                        "npn_critique_engagement.moderate.no_pick_by"
                        username=genre.no_pick.username
                      }}
                    </span>
                    <DButton
                      @action={{fn this.undoNoPick genre}}
                      @icon="arrow-rotate-left"
                      @ariaLabel="npn_critique_engagement.moderate.no_pick_undo"
                      class="btn-flat btn-small npn-moderate__no-pick-undo"
                    />
                  {{else}}
                    <span class="npn-moderate__pick-open">
                      {{i18n "npn_critique_engagement.moderate.pick_open"}}
                    </span>
                    <DButton
                      @action={{fn this.declareNoPick genre}}
                      @label="npn_critique_engagement.moderate.no_pick"
                      class="btn-flat btn-small npn-moderate__no-pick-button"
                    />
                  {{/if}}
                </li>
              {{/each}}
            </ul>
          {{else}}
            <p class="npn-moderate__empty">
              {{i18n "npn_critique_engagement.moderate.picks_empty"}}
            </p>
          {{/if}}
          <LinkTo
            @route="critique-editors-picks"
            class="npn-moderate__panel-link"
          >
            {{i18n "npn_critique_engagement.moderate.picks_link"}}
            {{dIcon "chevron-right"}}
          </LinkTo>
        </section>

        <section class="npn-moderate__panel npn-moderate__outreach">
          <h2>{{i18n "npn_critique_engagement.moderate.outreach_title"}}</h2>
          {{#if @model.outreach.length}}
            <ul class="npn-moderate__mini-list">
              {{#each @model.outreach as |row|}}
                <li class="npn-moderate__mini-row">
                  <a
                    class="npn-moderate__member"
                    href={{userPath row.username}}
                    data-user-card={{row.username}}
                  >
                    {{dBoundAvatarTemplate row.avatar_template "tiny"}}
                    <span>{{row.username}}</span>
                  </a>
                  <span class="npn-moderate__mini-meta">
                    {{i18n "npn_critique_engagement.admin.report.shared"}}:
                    {{row.created_topics}}
                    ·
                    {{i18n "npn_critique_engagement.admin.report.critiqued"}}:
                    {{row.topics_replied}}
                  </span>
                  <span class="npn-moderate__mini-contact">
                    {{#if row.claim}}
                      {{i18n
                        "npn_critique_engagement.admin.outreach.claimed_by"
                        username=row.claim.username
                      }}
                    {{else if row.last_outreach}}
                      {{dFormatDate row.last_outreach.created_at format="tiny"}}
                    {{else}}
                      {{i18n
                        "npn_critique_engagement.admin.outreach.never_contacted"
                      }}
                    {{/if}}
                  </span>
                </li>
              {{/each}}
            </ul>
          {{else}}
            <p class="npn-moderate__empty">
              {{i18n "npn_critique_engagement.admin.outreach.empty"}}
            </p>
          {{/if}}
          <LinkTo @route="critique-outreach" class="npn-moderate__panel-link">
            {{i18n "npn_critique_engagement.moderate.outreach_link"}}
            {{dIcon "chevron-right"}}
          </LinkTo>
        </section>

        <section class="npn-moderate__panel npn-moderate__welcome">
          <h2>{{i18n
              "npn_critique_engagement.admin.outreach.welcome_title"
            }}</h2>
          {{#if @model.welcome.length}}
            <ul class="npn-moderate__mini-list">
              {{#each @model.welcome as |row|}}
                <li class="npn-moderate__mini-row">
                  <a
                    class="npn-moderate__member"
                    href={{userPath row.username}}
                    data-user-card={{row.username}}
                  >
                    {{dBoundAvatarTemplate row.avatar_template "tiny"}}
                    <span>{{row.username}}</span>
                  </a>
                  <span class="npn-moderate__mini-meta">
                    {{i18n "npn_critique_engagement.admin.report.critiqued"}}:
                    {{row.topics_replied}}
                  </span>
                  <span class="npn-moderate__mini-contact">
                    {{#if row.last_outreach}}
                      {{dFormatDate row.last_outreach.created_at format="tiny"}}
                    {{else}}
                      {{i18n
                        "npn_critique_engagement.admin.outreach.never_contacted"
                      }}
                    {{/if}}
                  </span>
                </li>
              {{/each}}
            </ul>
          {{else}}
            <p class="npn-moderate__empty">
              {{i18n "npn_critique_engagement.admin.outreach.welcome_empty"}}
            </p>
          {{/if}}
          <LinkTo @route="critique-outreach" class="npn-moderate__panel-link">
            {{i18n "npn_critique_engagement.moderate.outreach_link"}}
            {{dIcon "chevron-right"}}
          </LinkTo>
        </section>
      </div>
    </div>
  </section>
  </template>
}
