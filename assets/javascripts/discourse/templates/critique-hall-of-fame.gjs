import { LinkTo } from "@ember/routing";
import { userPath } from "discourse/lib/url";
import dBoundAvatarTemplate from "discourse/ui-kit/helpers/d-bound-avatar-template";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import periodMonth from "../lib/period-month";

export default <template>
  <section class="npn-hall-of-fame">
    <header class="npn-hall-of-fame__header">
      <h1 class="npn-hall-of-fame__title">
        {{dIcon "trophy"}}
        {{i18n "npn_critique_engagement.hall_of_fame.title"}}
      </h1>
      <p class="npn-hall-of-fame__description">
        {{i18n "npn_critique_engagement.hall_of_fame.description"}}
      </p>
      <LinkTo
        @route="critique-leaderboard"
        class="npn-hall-of-fame__leaderboard-link"
      >
        {{i18n "npn_critique_engagement.hall_of_fame.leaderboard_link"}}
        {{dIcon "chevron-right"}}
      </LinkTo>
    </header>

    <section class="npn-hall-of-fame__pillars">
      <h2>{{i18n "npn_critique_engagement.hall_of_fame.pillars_title"}}</h2>
      {{#if @controller.model.pillars.length}}
        <ul class="npn-hall-of-fame__pillar-list">
          {{#each @controller.model.pillars as |pillar|}}
            <li class="npn-hall-of-fame__pillar">
              <a
                class="npn-hall-of-fame__member"
                href={{userPath pillar.username}}
                data-user-card={{pillar.username}}
              >
                {{dBoundAvatarTemplate pillar.avatar_template "large"}}
                <span class="npn-hall-of-fame__username">
                  {{pillar.username}}
                </span>
              </a>
              <span class="npn-hall-of-fame__granted">
                {{dFormatDate pillar.granted_at leaveAgo="true"}}
              </span>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="npn-hall-of-fame__empty">
          {{i18n "npn_critique_engagement.hall_of_fame.pillars_empty"}}
        </p>
      {{/if}}
    </section>

    <section class="npn-hall-of-fame__seasons">
      <h2>{{i18n "npn_critique_engagement.hall_of_fame.seasons_title"}}</h2>
      {{#if @controller.model.seasons.length}}
        <ul class="npn-hall-of-fame__season-list">
          {{#each @controller.model.seasons as |season|}}
            <li class="npn-hall-of-fame__season">
              <span class="npn-hall-of-fame__season-month">
                {{periodMonth season.period_start}}
              </span>
              <a
                class="npn-hall-of-fame__member"
                href={{userPath season.username}}
                data-user-card={{season.username}}
              >
                {{dBoundAvatarTemplate season.avatar_template "small"}}
                <span class="npn-hall-of-fame__username">
                  {{season.username}}
                </span>
              </a>
              <span class="npn-hall-of-fame__season-weighted">
                {{season.weighted_replies}}
                {{i18n "npn_critique_engagement.leaderboard.weighted"}}
              </span>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="npn-hall-of-fame__empty">
          {{i18n "npn_critique_engagement.hall_of_fame.seasons_empty"}}
        </p>
      {{/if}}
    </section>
  </section>
</template>
