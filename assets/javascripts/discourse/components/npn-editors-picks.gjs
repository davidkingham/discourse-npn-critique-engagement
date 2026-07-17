import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { userPath } from "discourse/lib/url";
import DButton from "discourse/ui-kit/d-button";
import DSelect from "discourse/ui-kit/d-select";
import dBoundAvatarTemplate from "discourse/ui-kit/helpers/d-bound-avatar-template";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import NpnTierBadge from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-tier-badge";

function weekLabel(weekStart) {
  return i18n("npn_critique_engagement.editors_picks.week_of", {
    date: new Date(weekStart).toLocaleDateString(undefined, {
      month: "long",
      day: "numeric",
      year: "numeric",
      timeZone: "UTC",
    }),
  });
}

function shiftWeek(weekStart, days) {
  const date = new Date(weekStart);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export default class NpnEditorsPicks extends Component {
  @service dialog;

  @tracked dataOverride = null;
  @tracked loading = false;

  get data() {
    return this.dataOverride ?? this.args.model;
  }

  @action
  async fetch(week, tag) {
    this.loading = true;
    try {
      const data = { week };
      if (tag) {
        data.tag = tag;
      }
      this.dataOverride = await ajax("/moderate/editors-picks.json", {
        data,
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  previousWeek() {
    this.fetch(shiftWeek(this.data.week_start, -7), this.data.tag);
  }

  @action
  nextWeek() {
    this.fetch(shiftWeek(this.data.week_start, 7), this.data.tag);
  }

  @action
  setTag(tag) {
    this.fetch(this.data.week_start, tag);
  }

  @action
  pick(topic) {
    this.dialog.yesNoConfirm({
      message: i18n("npn_critique_engagement.editors_picks.confirm_pick"),
      didConfirm: async () => {
        try {
          const result = await ajax("/moderate/editors-picks/pick", {
            type: "POST",
            data: { topic_id: topic.id },
          });
          this.dataOverride = {
            ...this.data,
            topics: this.data.topics.map((existing) =>
              existing.id === topic.id
                ? { ...existing, picked: true, picked_by: result.picked_by }
                : existing
            ),
          };
        } catch (error) {
          popupAjaxError(error);
        }
      },
    });
  }

  <template>
    <section class="npn-editors-picks">
      <header class="npn-editors-picks__header">
        <h1 class="npn-editors-picks__title">
          {{dIcon "star"}}
          {{i18n "npn_critique_engagement.editors_picks.title"}}
        </h1>
        <p class="npn-editors-picks__description">
          {{i18n "npn_critique_engagement.editors_picks.description"}}
        </p>
      </header>

      <div class="npn-editors-picks__controls">
        <DButton
          @action={{this.previousWeek}}
          @icon="chevron-left"
          @ariaLabel="npn_critique_engagement.editors_picks.previous_week"
          class="btn-default npn-editors-picks__week-nav"
        />
        <span class="npn-editors-picks__week">
          {{weekLabel this.data.week_start}}
        </span>
        <DButton
          @action={{this.nextWeek}}
          @icon="chevron-right"
          @ariaLabel="npn_critique_engagement.editors_picks.next_week"
          class="btn-default npn-editors-picks__week-nav"
        />

        <DSelect
          @value={{this.data.tag}}
          @onChange={{this.setTag}}
          class="npn-editors-picks__tag-filter"
          as |select|
        >
          {{#each this.data.tags as |tag|}}
            <select.Option @value={{tag}}>{{tag}}</select.Option>
          {{/each}}
        </DSelect>
      </div>

      {{#if this.data.topics.length}}
        <ul class="npn-editors-picks__grid">
          {{#each this.data.topics as |topic|}}
            <li class="npn-editors-picks__card">
              <a class="npn-editors-picks__image-link" href={{topic.url}}>
                {{#if topic.image_url}}
                  <img
                    class="npn-editors-picks__image"
                    src={{topic.image_url}}
                    alt=""
                    loading="lazy"
                  />
                {{else}}
                  <div class="npn-editors-picks__image --placeholder">
                    {{dIcon "image"}}
                  </div>
                {{/if}}
              </a>

              <div class="npn-editors-picks__body">
                <a class="npn-editors-picks__topic" href={{topic.url}}>
                  {{topic.title}}
                </a>

                <a
                  class="npn-editors-picks__member"
                  href={{userPath topic.username}}
                  data-user-card={{topic.username}}
                >
                  {{dBoundAvatarTemplate topic.avatar_template "small"}}
                  <span>{{topic.username}}</span>
                </a>

                {{#if topic.score}}
                  <div class="npn-editors-picks__standing">
                    <NpnTierBadge @tier={{topic.score.tier}} />
                    <span
                      class="npn-editors-picks__score"
                    >{{topic.score.score}}</span>
                    <span class="npn-editors-picks__counts">
                      {{i18n "npn_critique_engagement.admin.report.critiqued"}}:
                      {{topic.score.topics_replied}}
                      ·
                      {{i18n "npn_critique_engagement.admin.report.shared"}}:
                      {{topic.score.created_topics}}
                    </span>
                  </div>
                {{else}}
                  <div class="npn-editors-picks__standing --none">
                    {{i18n "npn_critique_engagement.editors_picks.no_standing"}}
                  </div>
                {{/if}}

                <div class="npn-editors-picks__meta">
                  {{i18n "npn_critique_engagement.editors_picks.posted"}}
                  {{dFormatDate topic.created_at format="tiny"}}
                </div>

                {{#if topic.picked}}
                  <div class="npn-editors-picks__picked">
                    {{dIcon "star"}}
                    {{#if topic.picked_by}}
                      {{i18n
                        "npn_critique_engagement.editors_picks.picked_by"
                        username=topic.picked_by.username
                      }}
                    {{/if}}
                  </div>
                {{else}}
                  <DButton
                    @action={{fn this.pick topic}}
                    @icon="star"
                    @label="npn_critique_engagement.editors_picks.pick"
                    class="btn-primary btn-small npn-editors-picks__pick"
                  />
                {{/if}}
              </div>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="npn-editors-picks__empty">
          {{i18n "npn_critique_engagement.editors_picks.no_images"}}
        </p>
      {{/if}}
    </section>
  </template>
}
