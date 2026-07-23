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
import NpnEditorsPickModal from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-editors-pick-modal";
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
  @service modal;
  @service router;

  // Local pick/unpick updates, keyed to the model they were applied on so a
  // route refresh (week/tag navigation, back button) discards them.
  @tracked dataOverride = null;

  get data() {
    if (this.dataOverride?.model === this.args.model) {
      return this.dataOverride.data;
    }
    return this.args.model;
  }

  navigate(week, tag) {
    this.router.transitionTo({ queryParams: { week, tag: tag ?? null } });
  }

  @action
  previousWeek() {
    this.navigate(shiftWeek(this.data.week_start, -7), this.data.tag);
  }

  @action
  nextWeek() {
    this.navigate(shiftWeek(this.data.week_start, 7), this.data.tag);
  }

  @action
  setTag(tag) {
    this.navigate(this.data.week_start, tag);
  }

  updateTopic(topicId, changes) {
    this.dataOverride = {
      model: this.args.model,
      data: {
        ...this.data,
        topics: this.data.topics.map((existing) =>
          existing.id === topicId ? { ...existing, ...changes } : existing
        ),
      },
    };
  }

  @action
  pick(topic) {
    const options = topic.genre_options ?? [];
    let defaultGenre = null;
    if (this.data.tag && options.includes(this.data.tag)) {
      defaultGenre = this.data.tag;
    } else if (options.length === 1) {
      defaultGenre = options[0];
    }

    this.modal.show(NpnEditorsPickModal, {
      model: {
        topic,
        defaultGenre,
        onPicked: (result) => {
          if (result.pending) {
            this.updateTopic(topic.id, { pending: result.pending });
          } else {
            this.updateTopic(topic.id, {
              picked: true,
              picked_by: result.picked_by,
            });
          }
        },
      },
    });
  }

  @action
  async undo(topic) {
    try {
      await ajax("/moderate/editors-picks/unpick", {
        type: "POST",
        data: { topic_id: topic.id },
      });
      this.updateTopic(topic.id, { pending: null });
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  removePick(topic) {
    this.dialog.yesNoConfirm({
      message: i18n("npn_critique_engagement.editors_picks.remove_confirm"),
      didConfirm: async () => {
        try {
          await ajax("/moderate/editors-picks/unpick", {
            type: "POST",
            data: { topic_id: topic.id },
          });
          this.updateTopic(topic.id, { picked: false, picked_by: null });
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

                <div
                  class="npn-editors-picks__picks-history"
                  title={{i18n
                    "npn_critique_engagement.editors_picks.recent_picks_hint"
                  }}
                >
                  {{dIcon "star"}}
                  {{i18n
                    "npn_critique_engagement.editors_picks.recent_picks"
                    count=topic.recent_picks
                  }}
                </div>

                {{#if topic.pending}}
                  <div class="npn-editors-picks__picked --pending">
                    {{dIcon "star"}}
                    {{#if topic.pending.genre}}
                      {{i18n
                        "npn_critique_engagement.editors_picks.picked_for"
                        username=topic.pending.username
                        genre=topic.pending.genre
                      }}
                    {{else}}
                      {{i18n
                        "npn_critique_engagement.editors_picks.picked_by"
                        username=topic.pending.username
                      }}
                    {{/if}}
                    <span class="npn-editors-picks__pending-note">
                      {{i18n
                        "npn_critique_engagement.editors_picks.pending_note"
                      }}
                    </span>
                  </div>
                  <DButton
                    @action={{fn this.undo topic}}
                    @icon="arrow-rotate-left"
                    @label="npn_critique_engagement.editors_picks.undo"
                    class="btn-default btn-small npn-editors-picks__undo"
                  />
                {{else if topic.picked}}
                  <div class="npn-editors-picks__picked">
                    {{dIcon "star"}}
                    {{#if topic.picked_by.genre}}
                      {{i18n
                        "npn_critique_engagement.editors_picks.picked_for"
                        username=topic.picked_by.username
                        genre=topic.picked_by.genre
                      }}
                    {{else if topic.picked_by}}
                      {{i18n
                        "npn_critique_engagement.editors_picks.picked_by"
                        username=topic.picked_by.username
                      }}
                    {{/if}}
                  </div>
                  <DButton
                    @action={{fn this.removePick topic}}
                    @icon="xmark"
                    @label="npn_critique_engagement.editors_picks.remove"
                    class="btn-flat btn-small npn-editors-picks__remove"
                  />
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
