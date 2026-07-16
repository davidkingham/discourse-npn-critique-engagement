import { trustHTML } from "@ember/template";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import NpnTierBadge from "../../components/npn-tier-badge";
import periodMonth from "../../lib/period-month";

function tierName(tier) {
  return i18n(`npn_critique_engagement.tiers.${tier}`);
}

function nextActionMessage(nextAction) {
  if (!nextAction) {
    return;
  }

  const prefix = "npn_critique_engagement.impact.next_action";
  switch (nextAction.type) {
    case "start":
      return i18n(`${prefix}.start`);
    case "at_top":
      return i18n(`${prefix}.at_top`);
    case "keep_going":
      return i18n(`${prefix}.keep_going`, {
        tier: tierName(nextAction.target_tier),
      });
    case "critiques_needed":
      return i18n(`${prefix}.critiques_needed`, {
        count: nextAction.count,
        tier: tierName(nextAction.target_tier),
      });
  }
}

function pillarProgress(pillar) {
  return i18n("npn_critique_engagement.impact.badges.pillar_progress", {
    count: pillar.excellent_months,
    window: pillar.window_months,
    required: pillar.required_months,
  });
}

function historyBarStyle(row, history) {
  const max = Math.max(...history.map((entry) => entry.weighted_replies), 1);
  return trustHTML(`--npn-bar-scale: ${row.weighted_replies / max}`);
}

export default <template>
  <div class="npn-impact">
    <header class="npn-impact__header">
      <h2 class="npn-impact__title">
        {{i18n "npn_critique_engagement.impact.title"}}
      </h2>
      <p class="npn-impact__private-note">
        {{dIcon "lock"}}
        {{i18n "npn_critique_engagement.impact.private_note"}}
      </p>
    </header>

    <p class="npn-impact__next-action" role="note">
      {{dIcon "hand-holding-heart"}}
      {{nextActionMessage @controller.model.next_action}}
    </p>

    <section class="npn-impact__current">
      <h3>
        {{i18n "npn_critique_engagement.impact.this_month"}}
        ({{periodMonth @controller.model.period_start}})
      </h3>
      {{#if @controller.model.current}}
        <dl class="npn-impact__stats">
          <div class="npn-impact__stat">
            <dt>{{i18n "npn_critique_engagement.impact.tier_label"}}</dt>
            <dd><NpnTierBadge @tier={{@controller.model.current.tier}} /></dd>
          </div>
          <div class="npn-impact__stat">
            <dt>{{i18n "npn_critique_engagement.impact.weighted_label"}}</dt>
            <dd>{{@controller.model.current.weighted_replies}}</dd>
          </div>
          <div class="npn-impact__stat">
            <dt>{{i18n "npn_critique_engagement.impact.critiqued_label"}}</dt>
            <dd>{{@controller.model.current.topics_replied}}</dd>
          </div>
          <div class="npn-impact__stat">
            <dt>{{i18n "npn_critique_engagement.impact.shared_label"}}</dt>
            <dd>{{@controller.model.current.created_topics}}</dd>
          </div>
          <div class="npn-impact__stat">
            <dt>{{i18n "npn_critique_engagement.impact.ratio_label"}}</dt>
            <dd>{{@controller.model.current.ratio}}</dd>
          </div>
        </dl>
      {{else}}
        <p class="npn-impact__empty">
          {{i18n "npn_critique_engagement.impact.no_activity"}}
        </p>
      {{/if}}
    </section>

    <section class="npn-impact__badges">
      <h3>{{i18n "npn_critique_engagement.impact.badges.title"}}</h3>
      <ul class="npn-impact__badge-list">
        {{#if @controller.model.badge_progress.contributor_on_track}}
          <li class="npn-impact__badge-progress">
            {{dIcon "medal"}}
            {{i18n
              "npn_critique_engagement.impact.badges.contributor_on_track"
            }}
          </li>
        {{/if}}
        {{#if @controller.model.badge_progress.supporter_on_track}}
          <li class="npn-impact__badge-progress">
            {{dIcon "award"}}
            {{i18n "npn_critique_engagement.impact.badges.supporter_on_track"}}
          </li>
        {{/if}}
        <li class="npn-impact__badge-progress">
          {{dIcon "trophy"}}
          {{pillarProgress @controller.model.badge_progress.pillar}}
        </li>
      </ul>
    </section>

    <section class="npn-impact__history">
      <h3>{{i18n "npn_critique_engagement.impact.history.title"}}</h3>
      {{#if @controller.model.history.length}}
        <ol class="npn-impact__history-list">
          {{#each @controller.model.history as |row|}}
            <li
              class="npn-impact__history-row"
              style={{historyBarStyle row @controller.model.history}}
            >
              <span class="npn-impact__history-month">
                {{periodMonth row.period_start}}
              </span>
              <span class="npn-impact__history-bar" aria-hidden="true"></span>
              <span class="npn-impact__history-value">
                {{row.weighted_replies}}
              </span>
              <NpnTierBadge @tier={{row.tier}} />
            </li>
          {{/each}}
        </ol>
      {{else}}
        <p class="npn-impact__empty">
          {{i18n "npn_critique_engagement.impact.history.empty"}}
        </p>
      {{/if}}
    </section>
  </div>
</template>
