import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const TIER_ICONS = {
  excellent: "trophy",
  healthy: "medal",
  watch: "eye",
  priority_outreach: "hand-holding-heart",
  low_activity: "moon",
  new_member: "seedling",
};

function tierIcon(tier) {
  return TIER_ICONS[tier] ?? "medal";
}

function tierLabel(tier) {
  return i18n(`npn_critique_engagement.tiers.${tier}`);
}

function tierClass(tier) {
  return `npn-tier-badge --${tier}`;
}

export default <template>
  {{#if @tier}}
    <span class={{tierClass @tier}} ...attributes>
      {{dIcon (tierIcon @tier)}}
      <span class="npn-tier-badge__label">{{tierLabel @tier}}</span>
    </span>
  {{/if}}
</template>
