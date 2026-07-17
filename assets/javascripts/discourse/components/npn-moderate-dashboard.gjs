import { LinkTo } from "@ember/routing";
import getURL from "discourse/lib/get-url";
import { userPath } from "discourse/lib/url";
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

export default <template>
  <section class="npn-moderate">
    <header class="npn-moderate__header">
      <h1 class="npn-moderate__title">
        {{dIcon "hand-holding-heart"}}
        {{i18n "npn_critique_engagement.moderate.title"}}
      </h1>
      <p class="npn-moderate__description">
        {{i18n "npn_critique_engagement.moderate.description"}}
      </p>
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

      <div class="npn-moderate__side">
        <section class="npn-moderate__panel npn-moderate__picks">
          <h2>{{i18n "npn_critique_engagement.moderate.picks_title"}}</h2>
          <p class="npn-moderate__hint">
            {{i18n "npn_critique_engagement.moderate.picks_hint"}}
          </p>
          {{#if @model.pick_status.length}}
            <ul class="npn-moderate__pick-list">
              {{#each @model.pick_status as |genre|}}
                <li class="npn-moderate__pick-row">
                  <a class="npn-moderate__pick-tag" href={{tagUrl genre.tag}}>
                    {{genre.tag}}
                  </a>
                  {{#if genre.picked}}
                    <a class="npn-moderate__pick-done" href={{genre.topic_url}}>
                      {{dIcon "check"}}
                      {{i18n
                        "npn_critique_engagement.moderate.picked_by"
                        username=genre.picked_by
                      }}
                    </a>
                  {{else}}
                    <span class="npn-moderate__pick-open">
                      {{i18n "npn_critique_engagement.moderate.pick_open"}}
                    </span>
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
