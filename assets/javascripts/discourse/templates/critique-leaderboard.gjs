import { LinkTo } from "@ember/routing";
import { userPath } from "discourse/lib/url";
import dBoundAvatarTemplate from "discourse/ui-kit/helpers/d-bound-avatar-template";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import NpnTierBadge from "../components/npn-tier-badge";
import periodMonth from "../lib/period-month";

function rank(index) {
  return index + 1;
}

export default <template>
  <section class="npn-leaderboard">
    <header class="npn-leaderboard__header">
      <h1 class="npn-leaderboard__title">
        {{dIcon "ranking-star"}}
        {{i18n "npn_critique_engagement.leaderboard.title"}}
      </h1>
      <p class="npn-leaderboard__month">
        {{periodMonth @controller.model.period_start}}
      </p>
      <p class="npn-leaderboard__description">
        {{i18n "npn_critique_engagement.leaderboard.description"}}
      </p>
      <LinkTo
        @route="critique-hall-of-fame"
        class="npn-leaderboard__hall-of-fame-link"
      >
        {{i18n "npn_critique_engagement.leaderboard.hall_of_fame_link"}}
        {{dIcon "chevron-right"}}
      </LinkTo>
    </header>

    {{#if @controller.model.entries.length}}
      <ol class="npn-leaderboard__list">
        {{#each @controller.model.entries as |entry index|}}
          <li class="npn-leaderboard__entry">
            <span class="npn-leaderboard__rank">{{rank index}}</span>
            <a
              class="npn-leaderboard__member"
              href={{userPath entry.username}}
              data-user-card={{entry.username}}
            >
              {{dBoundAvatarTemplate entry.avatar_template "medium"}}
              <span class="npn-leaderboard__username">{{entry.username}}</span>
            </a>
            {{#if entry.tier}}
              <NpnTierBadge @tier={{entry.tier}} />
            {{/if}}
            <span class="npn-leaderboard__weighted">
              {{entry.weighted_replies}}
              <span class="npn-leaderboard__weighted-label">
                {{i18n "npn_critique_engagement.leaderboard.weighted"}}
              </span>
            </span>
          </li>
        {{/each}}
      </ol>
    {{else}}
      <p class="npn-leaderboard__empty">
        {{i18n "npn_critique_engagement.leaderboard.empty"}}
      </p>
    {{/if}}
  </section>
</template>
